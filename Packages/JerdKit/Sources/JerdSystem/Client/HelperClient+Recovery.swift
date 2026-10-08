import Foundation
import JerdFoundation

extension HelperClient {
    /// The one automatic restart of the helper in this app run.
    enum AutomaticRestart {
        case available
        case running(id: UUID, task: Task<Void, any Error>)
        case used

        var policyState: HelperRecoveryPolicy.Restart {
            switch self {
            case .available: .available
            case .running: .running
            case .used: .used
            }
        }
    }

    /// Waits for a running restart, so no call reads the daemon state or connects while the daemon
    /// is not registered. Without this, a call during the restart saw "no setup" or "Approved
    /// helper setup is required", and an approval could race the restart's `register()`.
    /// Cancellation ends the wait at once; the restart itself continues.
    /// - Throws: The error of the restart, which names what to do.
    func waitForRunningRestart() async throws {
        guard case .running(_, let task) = automaticRestart else { return }
        try await Self.wait(for: task, timeout: nil)
    }

    /// Waits until no restart runs. A failed restart is no error here: the caller continues.
    func waitForRestartToEnd() async throws {
        var waited: Set<UUID> = []
        while case .running(let id, let task) = automaticRestart, !waited.contains(id) {
            waited.insert(id)
            do {
                try await Self.wait(for: task, timeout: nil)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The restart failed; its own caller reports it.
            }
        }
    }

    /// Joins running restarts for a Reconnect. Returns true when one succeeded. After a failed one
    /// it checks again, because another Reconnect may have started a new restart meanwhile; so two
    /// `reregister()` calls never run in parallel.
    func joinRunningRestarts() async throws -> Bool {
        var joined: Set<UUID> = []
        while case .running(let id, let task) = automaticRestart, !joined.contains(id) {
            joined.insert(id)
            do {
                try await Self.wait(for: task, timeout: nil)
                completeJoinedRestart(id)
                return true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // It failed: check again, then restart.
            }
        }
        return false
    }

    /// Waits for `task` without cancelling it. Cancellation of the caller or the timeout ends only
    /// this wait (`ReplyGate`).
    static func wait(for task: Task<Void, any Error>, timeout: Duration?) async throws {
        try await ReplyGate<Void>.wait(cancellation: .readOnly, timeout: timeout) { gate in
            Task {
                do {
                    try await task.value
                    gate.resolve(.success(()))
                } catch {
                    gate.resolve(.failure(error))
                }
            }
        }
    }

    /// Runs `call` after a running restart. After a transport failure it follows
    /// `HelperRecoveryPolicy`: at most one restart of a stale helper and one retry of the call. A
    /// failure on a link from before a finished restart is retried on the new link. Every error
    /// that leaves is a `JerdError` or the call's own error.
    func recovering<Value: Sendable>(_ call: () async throws -> Value) async throws -> Value {
        try await waitForRunningRestart()
        let generation = finishedRestarts
        do {
            return try await call()
        } catch let failure as HelperTransportError {
            try await prepareRetry(after: failure, restartedSinceStart: finishedRestarts != generation)
            do {
                return try await call()
            } catch let again as HelperTransportError {
                throw HelperRecoveryPolicy.errorAfterRetry(again)
            }
        }
    }

    /// A retry waits for a running restart first: the restart closes the old link, which fails the
    /// calls on it. It closes only the failed link, so a late failure never closes a newer link.
    private func prepareRetry(after failure: HelperTransportError, restartedSinceStart: Bool) async throws {
        let step = HelperRecoveryPolicy.step(
            after: failure, restart: automaticRestart.policyState, holdsListeners: holdsListeners,
            restartedSinceStart: restartedSinceStart)
        switch step {
        case .fail(let error):
            throw error
        case .retry:
            try await waitForRunningRestart()
            if let link = failure.link { await connection.drop(link) }
        case .retryOnNewLink, .awaitRestartThenRetry:
            try await waitForRunningRestart()
        case .restartThenRetry:
            try await runRestart(finishing: .used)
        }
    }

    /// Registers the helper again, so launchd starts the helper file of this app. The user approved
    /// the helper before; hosts and trust do not change. Calls that start or fail meanwhile wait,
    /// so only one `reregister()` runs at a time. The automatic restart ends as `.used`; a manual
    /// Reconnect ends as `.available`.
    func runRestart(finishing final: AutomaticRestart) async throws {
        let (connection, registration) = (connection, registration)
        let id = UUID()
        let restart = Task {
            await connection.invalidate()
            try await registration.reregister()
        }
        automaticRestart = .running(id: id, task: restart)
        defer { finishRestart(id, as: final) }
        try await restart.value
    }

    /// Ends the restart `id`, unless it ended already or another restart replaced it.
    private func finishRestart(_ id: UUID, as final: AutomaticRestart) {
        guard case .running(let current, _) = automaticRestart, current == id else { return }
        finishedRestarts += 1
        automaticRestart = final
    }

    /// A Reconnect that joined the successful restart `id`: a later stale helper may be restarted
    /// automatically again.
    private func completeJoinedRestart(_ id: UUID) {
        if case .running(let current, _) = automaticRestart {
            guard current == id else { return }
            finishedRestarts += 1
        }
        automaticRestart = .available
    }
}

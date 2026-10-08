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

    /// Waits for a running automatic restart, so no call reads the daemon state or connects while
    /// the daemon is not registered. Without this, a call during the restart saw "no setup" or
    /// "Approved helper setup is required", and an approval could race the restart's `register()`.
    /// - Throws: The error of the restart, which names what to do.
    func waitForRunningRestart() async throws {
        guard case .running(_, let task) = automaticRestart else { return }
        try await task.value
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

    private func prepareRetry(after failure: HelperTransportError, restartedSinceStart: Bool) async throws {
        let step = HelperRecoveryPolicy.step(
            after: failure, restart: automaticRestart.policyState, holdsListeners: holdsListeners,
            restartedSinceStart: restartedSinceStart)
        switch step {
        case .fail(let error):
            throw error
        case .retry:
            await connection.invalidate()
        case .retryOnNewLink:
            break
        case .awaitRestartThenRetry:
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

    /// Ends the restart `id`, unless another restart replaced it meanwhile.
    private func finishRestart(_ id: UUID, as final: AutomaticRestart) {
        finishedRestarts += 1
        guard case .running(let current, _) = automaticRestart, current == id else { return }
        automaticRestart = final
    }
}

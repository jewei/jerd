import JerdFoundation

extension HelperClient {
    /// The one automatic restart of the helper in this app run.
    enum AutomaticRestart {
        case available
        case running(Task<Void, any Error>)
        case used

        var policyState: HelperRecoveryPolicy.Restart {
            switch self {
            case .available: .available
            case .running: .running
            case .used: .used
            }
        }
    }

    /// Runs `call`. After a transport failure it follows `HelperRecoveryPolicy`: at most one
    /// restart of a stale helper and one retry of the call. Every error that leaves is a `JerdError`
    /// or the call's own error.
    func recovering<Value: Sendable>(_ call: () async throws -> Value) async throws -> Value {
        do {
            return try await call()
        } catch let failure as HelperTransportError {
            try await prepareRetry(after: failure)
            do {
                return try await call()
            } catch let again as HelperTransportError {
                throw HelperRecoveryPolicy.errorAfterRetry(again)
            }
        }
    }

    private func prepareRetry(after failure: HelperTransportError) async throws {
        let step = HelperRecoveryPolicy.step(
            after: failure, restart: automaticRestart.policyState, holdsListeners: holdsListeners)
        switch step {
        case .fail(let error):
            throw error
        case .retry:
            await connection.invalidate()
        case .awaitRestartThenRetry:
            guard case .running(let restart) = automaticRestart else { return }
            try await restart.value
        case .restartThenRetry:
            try await restartStaleHelper()
        }
    }

    /// Registers the helper again, so launchd starts the helper file of this app. The user approved
    /// the helper before; hosts and trust do not change. Calls that fail meanwhile wait for it.
    private func restartStaleHelper() async throws {
        let (connection, registration) = (connection, registration)
        let restart = Task {
            await connection.invalidate()
            try await registration.reregister()
        }
        automaticRestart = .running(restart)
        defer { automaticRestart = .used }
        try await restart.value
    }
}

import JerdFoundation

/// How an in-memory service answers a start or a stop.
public enum ServiceBehavior: Equatable, Sendable {
    case succeed
    /// The call throws. A start also leaves the service `failed` with this reason.
    case fail(String)
    /// A stop times out: the service becomes `stuck` and the call throws.
    case stuck(String)
    /// The call waits until its task is cancelled, for quit tests and snapshots.
    case suspend

    /// Waits for cancellation, then throws.
    static func waitForCancellation() async throws -> Never {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        throw CancellationError()
    }
}

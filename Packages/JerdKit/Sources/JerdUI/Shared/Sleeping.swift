/// Waits for a duration. The poller sleeps through this port, so tests control time.
public protocol Sleeping: Sendable {
    /// Returns after `duration`, or throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}

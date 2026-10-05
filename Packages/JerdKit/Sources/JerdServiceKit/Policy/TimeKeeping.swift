/// The clock that readiness polling uses. Tests inject a clock that advances without waiting.
public protocol TimeKeeping: Sendable {
    /// The current instant.
    func now() -> ContinuousClock.Instant
    /// Waits for `duration`. Throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}

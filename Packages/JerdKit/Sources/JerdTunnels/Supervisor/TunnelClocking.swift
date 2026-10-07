/// The time source of the tunnel monitor. Tests use a manual clock, so backoff and readiness tests
/// never wait for real time.
public protocol TunnelClocking: Sendable {
    /// The current instant.
    var now: ContinuousClock.Instant { get }
    /// Waits for `duration`. Throws `CancellationError` when the task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// The system continuous clock.
public struct TunnelClock: TunnelClocking {
    public init() {}

    public var now: ContinuousClock.Instant { ContinuousClock.now }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, clock: .continuous)
    }
}

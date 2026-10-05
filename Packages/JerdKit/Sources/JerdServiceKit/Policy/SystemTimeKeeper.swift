/// The real clock: `ContinuousClock`, which keeps counting while the Mac sleeps.
public struct SystemTimeKeeper: TimeKeeping {
    public init() {}

    public func now() -> ContinuousClock.Instant { ContinuousClock.now }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, clock: .continuous)
    }
}

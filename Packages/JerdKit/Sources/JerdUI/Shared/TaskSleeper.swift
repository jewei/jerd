/// The live sleeper: `Task.sleep` on the continuous clock.
public struct TaskSleeper: Sleeping {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

import JerdUI

/// A sleeper that never wakes until its task is cancelled, so fixtures never poll.
public struct IdleSleeper: Sleeping {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        while true {
            try await Task.sleep(for: .seconds(3600))
        }
    }
}

import Foundation

/// The time of the release commands: dates for `state.json` and the feed, and waits between feed
/// fetches. Tests use a fixed clock that does not wait.
protocol ReleaseClock: Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async throws
}

/// The system clock.
struct SystemReleaseClock: ReleaseClock {
    func now() -> Date { Date() }

    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

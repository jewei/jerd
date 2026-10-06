import Foundation

/// The time source of the manual harnesses: the date of an evidence record and every bounded wait.
/// Tests use a fake clock that moves forward on each sleep, so no test waits for real time.
protocol HarnessClock: Sendable {
    func now() -> Date
    func sleep(for duration: Duration) async throws
}

extension HarnessClock {
    /// Checks `condition` every `interval` until it is true or `limit` passes. Returns the last answer.
    func wait(
        upTo limit: Duration, every interval: Duration = .milliseconds(100), until condition: () -> Bool
    ) async throws -> Bool {
        let seconds = TimeInterval(limit.components.seconds) + TimeInterval(limit.components.attoseconds) / 1e18
        let deadline = now().addingTimeInterval(seconds)
        while !condition() {
            guard now() < deadline else { return false }
            try await sleep(for: interval)
        }
        return true
    }
}

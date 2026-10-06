import Foundation

/// The system clock of the manual harnesses.
struct SystemHarnessClock: HarnessClock {
    func now() -> Date { Date() }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

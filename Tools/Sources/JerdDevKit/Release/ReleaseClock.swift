import Foundation

/// The time of a release: the date of the changelog section and of the feed item. Tests use a fixed clock.
protocol ReleaseClock: Sendable {
    func now() -> Date
}

/// The system clock.
struct SystemReleaseClock: ReleaseClock {
    func now() -> Date { Date() }
}

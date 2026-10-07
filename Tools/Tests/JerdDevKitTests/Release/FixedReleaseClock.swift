import Foundation

@testable import JerdDevKit

/// A clock at a fixed time.
struct FixedReleaseClock: ReleaseClock {
    let date: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_791_288_000)) { self.date = date }

    func now() -> Date { date }
}

import Foundation
import os

@testable import JerdDevKit

/// A clock that starts at a fixed date and moves forward only when a harness sleeps.
final class FakeHarnessClock: HarnessClock {
    /// 2026-10-06T09:15:00Z.
    static let start = Date(timeIntervalSince1970: 1_791_278_100)

    private let current = OSAllocatedUnfairLock(initialState: FakeHarnessClock.start)
    private let sleeps = OSAllocatedUnfairLock(initialState: 0)

    func now() -> Date { current.withLock { $0 } }

    func sleep(for duration: Duration) async throws {
        let seconds = TimeInterval(duration.components.seconds) + TimeInterval(duration.components.attoseconds) / 1e18
        sleeps.withLock { $0 += 1 }
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    var sleepCount: Int { sleeps.withLock { $0 } }
}

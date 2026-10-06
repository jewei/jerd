import Foundation
import os

@testable import JerdDevKit

/// A clock at a fixed time that records each wait instead of waiting.
final class FixedReleaseClock: ReleaseClock {
    let date: Date
    private let waits = OSAllocatedUnfairLock(initialState: [Duration]())

    init(_ date: Date = Date(timeIntervalSince1970: 1_791_288_000)) { self.date = date }

    func now() -> Date { date }

    func sleep(for duration: Duration) async throws { waits.withLock { $0.append(duration) } }

    var sleeps: [Duration] { waits.withLock { $0 } }
}

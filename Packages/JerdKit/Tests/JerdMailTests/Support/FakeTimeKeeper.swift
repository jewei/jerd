import JerdServiceKit
import os

/// A clock that advances by the requested duration on each sleep, without waiting.
final class FakeTimeKeeper: TimeKeeping {
    private let start = ContinuousClock.now
    private let elapsed = OSAllocatedUnfairLock<Duration>(initialState: .zero)
    private let count = OSAllocatedUnfairLock(initialState: 0)

    /// The number of sleeps so far.
    var sleeps: Int { count.withLock { $0 } }

    func now() -> ContinuousClock.Instant { start + elapsed.withLock { $0 } }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        elapsed.withLock { $0 += duration }
        count.withLock { $0 += 1 }
        await Task.yield()
    }
}

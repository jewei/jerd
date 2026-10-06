import os

/// The cancel signal of one ping, because the exchange runs on its own thread outside any task.
final class PingCancellation: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    /// Throws `CancellationError` after `cancel()`, like `Task.checkCancellation()`.
    func check() throws {
        if state.withLock({ $0 }) { throw CancellationError() }
    }

    func cancel() { state.withLock { $0 = true } }
}

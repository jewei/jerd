import os

/// Records the signals that a fake send function received.
final class SentSignals: Sendable {
    private let storage = OSAllocatedUnfairLock<[Int32]>(initialState: [])
    var values: [Int32] { storage.withLock { $0 } }
    func record(_ signal: Int32) { storage.withLock { $0.append(signal) } }
}

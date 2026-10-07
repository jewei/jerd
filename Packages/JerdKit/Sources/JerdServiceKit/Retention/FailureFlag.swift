import os

/// A thread-safe flag that a callback sets once, for example the error handler of an enumerator.
final class FailureFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var isSet: Bool { state.withLock { $0 } }

    func set() { state.withLock { $0 = true } }
}

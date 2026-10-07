import Darwin
import JerdProcess
import os

/// Returns scripted `errno` values, one per call, and counts the calls.
final class CallSequence: Sendable {
    private let errors: [Int32]
    private let index = OSAllocatedUnfairLock(initialState: 0)

    init(errors: [Int32]) { self.errors = errors }

    var calls: Int { index.withLock { $0 } }

    var list: ProcessGroupInspector.List {
        { [self] _, _ in
            let error = index.withLock { index in
                defer { index += 1 }
                return errors[min(index, errors.count - 1)]
            }
            return (0, error)
        }
    }
}

import os

@testable import JerdDevKit

/// A process table. A process can stay alive for a number of executable lookups, and ignore SIGTERM.
final class FakeProcessInspector: ProcessInspecting {
    struct Entry {
        var path: String
        var remainingLookups: Int
        var ignoresTerminate: Bool
    }

    private let table = OSAllocatedUnfairLock(initialState: [Int32: Entry]())
    private let terminated = OSAllocatedUnfairLock(initialState: [Int32]())

    func add(_ pid: Int32, path: String, lookups: Int = .max, ignoresTerminate: Bool = false) {
        table.withLock { $0[pid] = Entry(path: path, remainingLookups: lookups, ignoresTerminate: ignoresTerminate) }
    }

    func executablePath(of pid: Int32) -> String? {
        table.withLock { table in
            guard var entry = table[pid] else { return nil }
            guard entry.remainingLookups > 0 else {
                table[pid] = nil
                return nil
            }
            entry.remainingLookups -= 1
            table[pid] = entry
            return entry.path
        }
    }

    func terminate(_ pid: Int32) -> Bool {
        terminated.withLock { $0.append(pid) }
        return table.withLock { table in
            guard let entry = table[pid] else { return false }
            if !entry.ignoresTerminate { table[pid] = nil }
            return true
        }
    }

    var terminatedPIDs: [Int32] { terminated.withLock { $0 } }
}

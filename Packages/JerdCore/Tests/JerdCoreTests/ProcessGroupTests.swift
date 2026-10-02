import Darwin
import Foundation
import Testing
@testable import JerdCore

struct ProcessGroupTests {
    @Test func zeroWithAnErrorIsUnknownButZeroWithoutAnErrorIsEmpty() {
        let failed = ProcessGroupInspector { _, _ in (0, EIO) }
        let empty = ProcessGroupInspector { _, _ in (0, 0) }
        #expect(failed.liveMembers(of: getpgrp()) == nil)
        #expect(empty.liveMembers(of: getpgrp()) == [])
        // A native empty result must not inherit errno from an earlier operation.
        errno = EIO
        #expect(ProcessGroupInspector().liveMembers(of: .max) == [])
    }

    @Test func interruptionRetriesAreBoundedAndFullBuffersAreUnknown() {
        let sequence = GroupListSequence(errors: [EINTR, 0])
        #expect(ProcessGroupInspector(list: sequence.list).liveMembers(of: getpgrp()) == [])
        #expect(sequence.calls == 2)
        let interrupted = GroupListSequence(errors: [EINTR, EINTR, EINTR, 0])
        #expect(ProcessGroupInspector(list: interrupted.list).liveMembers(of: getpgrp()) == nil)
        #expect(interrupted.calls == 3)
        let full = ProcessGroupInspector { _, pids in (Int32(pids.count), 0) }
        #expect(full.liveMembers(of: getpgrp()) == nil)
    }

    @Test func membersThatExitDuringInspectionAreOmitted() {
        let inspector = ProcessGroupInspector { _, pids in
            pids[0] = getpid()
            pids[1] = .max
            return (2, 0)
        }
        #expect(inspector.liveMembers(of: getpgrp()) == [getpid()])
    }
}

private final class GroupListSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let errors: [Int32]
    private var index = 0
    init(errors: [Int32]) { self.errors = errors }
    var calls: Int { lock.withLock { index } }
    func list(_ group: pid_t, _ pids: UnsafeMutableBufferPointer<pid_t>) -> (count: Int32, error: Int32) {
        lock.withLock {
            let error = errors[min(index, errors.count - 1)]
            index += 1
            return (0, error)
        }
    }
}

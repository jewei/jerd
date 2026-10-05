import Darwin
import JerdProcess
import Testing
import os

@Suite struct ProcessGroupInspectorTests {
    @Test func zeroWithAnErrorIsUnknownButZeroWithoutAnErrorIsEmpty() {
        #expect(ProcessGroupInspector(list: { _, _ in (0, EIO) }).members(of: getpgrp()) == .unknown)
        #expect(ProcessGroupInspector(list: { _, _ in (0, 0) }).members(of: getpgrp()) == .empty)
        // A native empty answer must not inherit errno from an earlier call.
        errno = EIO
        #expect(ProcessGroupInspector().members(of: .max) == .empty)
    }

    @Test func interruptionRetriesAreBoundedAndFullOrNegativeCountsAreUnknown() {
        let once = CallSequence(errors: [EINTR, 0])
        #expect(ProcessGroupInspector(list: once.list).members(of: 1_000) == .empty)
        #expect(once.calls == 2)
        let always = CallSequence(errors: [EINTR, EINTR, EINTR, 0])
        #expect(ProcessGroupInspector(list: always.list).members(of: 1_000) == .unknown)
        #expect(always.calls == ProcessGroupInspector.attempts)
        #expect(ProcessGroupInspector(list: { _, pids in (Int32(pids.count), 0) }).members(of: 1_000) == .unknown)
        #expect(ProcessGroupInspector(list: { _, _ in (-1, 0) }).members(of: 1_000) == .unknown)
    }

    @Test func membersThatExitDuringInspectionAreOmitted() {
        let inspector = ProcessGroupInspector { _, pids in
            pids[0] = getpid()
            pids[1] = .max
            return (2, 0)
        }
        #expect(inspector.members(of: getpgrp()) == .members([getpid()]))
    }

    @Test func anUnsafePIDOrAnUnknownLivenessMakesTheAnswerUnknown() {
        let listsInit = ProcessGroupInspector { _, pids in
            pids[0] = 1
            return (1, 0)
        }
        #expect(listsInit.members(of: 1_000) == .unknown)
        let unknownLiveness = ProcessGroupInspector(
            list: { _, pids in
                pids[0] = 4_000
                return (1, 0)
            }, liveness: { _ in nil })
        #expect(unknownLiveness.members(of: 1_000) == .unknown)
    }

    @Test func onlyAProvenEmptyGroupHasNoOtherMembers() {
        let leaderOnly = ProcessGroupInspector(
            list: { _, pids in
                pids[0] = 4_000
                return (1, 0)
            }, liveness: { _ in true })
        #expect(!leaderOnly.mayHaveMembers(otherThan: 4_000, in: 4_000))
        #expect(leaderOnly.mayHaveMembers(otherThan: 4_001, in: 4_000))
        #expect(ProcessGroupInspector(list: { _, _ in (0, EIO) }).mayHaveMembers(otherThan: 4_000, in: 4_000))
        #expect(!ProcessGroupInspector(list: { _, _ in (0, 0) }).mayHaveMembers(otherThan: 4_000, in: 4_000))
    }
}

/// Returns scripted `errno` values, one per call, and counts the calls.
private final class CallSequence: Sendable {
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

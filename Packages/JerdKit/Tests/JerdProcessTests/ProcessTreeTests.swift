import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdProcess

@Suite struct ProcessTreeTests {
    private static func member(_ pid: pid_t, group: pid_t = 100, started: UInt64 = 7) -> ProcessTree.Member {
        ProcessTree.Member(processID: pid, groupID: group, startedSeconds: started, startedMicroseconds: 0)
    }

    /// 100 → 101 → 102 (its own session) and 100 → 103 (a zombie).
    private static let children: ProcessTree.Children = { parent in
        [100: [101, 103], 101: [102]][parent] ?? []
    }

    private static let inspect: ProcessTree.Inspect = { pid in
        switch pid {
        case 101: .live(member(101))
        case 102: .live(member(102, group: 102))
        default: .gone
        }
    }

    @Test func theWalkFindsDescendantsOutsideTheGroupAndSkipsZombies() {
        let tree = ProcessTree(children: Self.children, inspect: Self.inspect)
        #expect(tree.descendants(of: [100]) == [Self.member(101), Self.member(102, group: 102)])
    }

    @Test func aFailedListOrAnUnknownProcessMakesTheAnswerUnknown() {
        let failedList = ProcessTree(children: { $0 == 101 ? nil : Self.children($0) }, inspect: Self.inspect)
        #expect(failedList.descendants(of: [100]) == nil)
        let unknown = ProcessTree(children: Self.children, inspect: { $0 == 102 ? .unknown : Self.inspect($0) })
        #expect(unknown.descendants(of: [100]) == nil)
    }

    @Test func aTreeAboveTheCapacityIsUnknown() {
        let wide = ProcessTree(
            children: { $0 == 100 ? Array(1_000..<pid_t(1_000 + ProcessTree.capacity)) : [] },
            inspect: { .live(Self.member($0)) })
        #expect(wide.descendants(of: [100]) == nil)
    }

    @Test func aReusedPIDIsNotTheTrackedProcess() {
        let tree = ProcessTree(children: { _ in [] }, inspect: { .live(Self.member($0, started: 8)) })
        #expect(tree.current(Self.member(101)) == .gone)
        #expect(tree.current(Self.member(101, started: 8)) == .live(Self.member(101, started: 8)))
    }

    @Test func trackedDescendantsForgetOnlyProcessesThatAreProvenGone() {
        let tracked = TrackedDescendants()
        tracked.track([Self.member(101), Self.member(102)])
        tracked.track([Self.member(101)])
        #expect(tracked.all.count == 2)
        let tree = ProcessTree(children: { _ in [] }, inspect: { $0 == 101 ? .gone : .unknown })
        #expect(tracked.refresh(using: tree) == [.unknown])
        #expect(tracked.all == [Self.member(102)])
    }

    @Test func theSystemTreeSeesAChildThatLeftTheGroup() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let binary = try await Fixtures.shared.executable("orphan-controller")
        let log = folder.path("orphan-controller.log")
        let token = try await supervisor.start(
            ProcessRequest(executable: binary, workingDirectory: folder.url), log: ProcessLogFile(url: log))
        #expect(await eventually { pid_t(text(log).trimmingCharacters(in: .newlines)) != nil })
        let child = try #require(pid_t(text(log).trimmingCharacters(in: .newlines)))
        let leader = try #require(await supervisor.processID(of: token))
        let found = try #require(ProcessTree().descendants(of: [leader]))
        #expect(found.map(\.processID) == [child])
        #expect(found.first?.groupID == child)
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(5))) == .stopped)
        #expect(await eventually { isGone(child) })
    }
}

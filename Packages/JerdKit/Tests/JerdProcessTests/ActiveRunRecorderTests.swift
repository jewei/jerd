import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct ActiveRunRecorderTests {
    private func clearance(_ folder: TemporaryDirectory) throws -> (StartClearance, InstanceLock) {
        let location = DataLayout(root: folder.url).mail.record
        try OwnedDirectory.create(location.folder)
        let lock = try InstanceLock.acquire(at: location.lockFile, messages: .init(unavailable: "x", busy: "y"))
        return (try StartGate().requireStopped(location, holding: lock), lock)
    }

    @Test func aLiveChildGetsAFullRecordWithTheGracefulSignal() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (cleared, lock) = try clearance(folder)
        defer { lock.release() }
        let supervisor = ProcessSupervisor()
        let token = try await supervisor.start(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("sleep.log")))
        let pid = try #require(await supervisor.processID(of: token))
        try ActiveRunRecorder().record(processID: pid, runtimeID: "mail-1", gracefulSignal: SIGINT, clearance: cleared)
        let record = try ActiveRunRecordFile.read(cleared.location.recordFile)
        #expect(record.identity?.processID == pid)
        #expect(record.controller?.processID == getpid())
        #expect(record.gracefulSignal == SIGINT)
        #expect(await supervisor.stop(token, policy: .forceful()) == .stopped)
    }

    @Test func anEarlyExitedMasterStillGetsAConservativeRecord() async throws {
        let folder = try TemporaryDirectory(" early master exit")
        defer { folder.remove() }
        let (cleared, lock) = try clearance(folder)
        defer { lock.release() }
        touch(folder.path("exit-master"))
        let supervisor = ProcessSupervisor()
        let service = try await Fixtures.shared.executable("orphan-service")
        let token = try await supervisor.start(
            ProcessRequest(executable: service, workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("s.log")))
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
        let pid = try #require(await supervisor.processID(of: token))
        #expect(throws: JerdError.self) {
            try ActiveRunRecorder().record(
                processID: pid, runtimeID: "fixture", gracefulSignal: SIGTERM, clearance: cleared)
        }
        let record = try ActiveRunRecordFile.read(cleared.location.recordFile)
        #expect(record.identity == nil)
        #expect(record.controller != nil)
        #expect(throws: JerdError.self) { try StartGate().requireStopped(cleared.location, holding: lock) }
        touch(folder.path("finish-child"))
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(3))) == .stopped)
        _ = try StartGate().requireStopped(cleared.location, holding: lock)
    }

    @Test func aFailedControllerCaptureStillRecordsTheChild() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (cleared, lock) = try clearance(folder)
        defer { lock.release() }
        let child = IdentityFactory.make(pid: 4_242)
        let recorder = ActiveRunRecorder { pid in
            guard pid == child.processID else { throw JerdError.unavailable("Cannot inspect Jerd.") }
            return child
        }
        try recorder.record(processID: 4_242, runtimeID: "x", gracefulSignal: SIGTERM, clearance: cleared)
        let record = try ActiveRunRecordFile.read(cleared.location.recordFile)
        #expect(record.identity == child)
        #expect(record.controller == nil)
    }

    @Test func aReleasedLockInvalidatesTheClearance() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (cleared, lock) = try clearance(folder)
        lock.release()
        #expect(throws: JerdError.invalid("Hold the lock of Mail before saving its process record.")) {
            try ActiveRunRecorder().record(
                processID: getpid(), runtimeID: "x", gracefulSignal: SIGTERM, clearance: cleared)
        }
        #expect(FileProbe.presence(at: cleared.location.recordFile) == .absent)
    }

    /// Fixed review M2: a clearance allows a new record only. A second save with the same clearance
    /// never replaces the record of a process that may still run.
    @Test func aSecondRecordWithTheSameClearanceIsRefusedAndTheFirstIsKept() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (cleared, lock) = try clearance(folder)
        defer { lock.release() }
        let first = IdentityFactory.make(pid: 4_242)
        let second = IdentityFactory.make(pid: 4_343)
        let recorder = ActiveRunRecorder { pid in pid == second.processID ? second : first }
        try recorder.record(processID: 4_242, runtimeID: "first", gracefulSignal: SIGTERM, clearance: cleared)
        #expect(
            throws: JerdError.unavailable(
                "A process record of Mail already exists. It was preserved, and no new record was saved.")
        ) {
            try recorder.record(processID: 4_343, runtimeID: "second", gracefulSignal: SIGTERM, clearance: cleared)
        }
        #expect(try ActiveRunRecordFile.read(cleared.location.recordFile).identity == first)
        // After the first process stopped and its record was removed, the same clearance serves again.
        try ActiveRunRecordFile.remove(cleared.location, holding: lock)
        try recorder.record(processID: 4_343, runtimeID: "second", gracefulSignal: SIGTERM, clearance: cleared)
        #expect(try ActiveRunRecordFile.read(cleared.location.recordFile).identity == second)
    }

    /// Fixed review M2: the public writes require the lock of the record.
    @Test func publicRecordWritesRequireTheMatchingLock() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let (cleared, lock) = try clearance(folder)
        let record = ActiveRunRecord(
            processID: 4_242, runtimeID: "x", identity: nil, controller: nil, gracefulSignal: SIGTERM)
        let refusal = JerdError.invalid("Hold the lock of Storage before changing its process record.")
        try OwnedDirectory.create(layout.storage.root)
        #expect(throws: refusal) { try ActiveRunRecordFile.write(record, at: layout.storage.record, holding: lock) }
        #expect(throws: refusal) { try ActiveRunRecordFile.create(record, at: layout.storage.record, holding: lock) }
        #expect(FileProbe.presence(at: layout.storage.activeRunFile) == .absent)
        try ActiveRunRecordFile.write(record, at: cleared.location, holding: lock)
        #expect(try ActiveRunRecordFile.read(cleared.location.recordFile) == record)
        lock.release()
        #expect(throws: JerdError.self) { try ActiveRunRecordFile.write(record, at: cleared.location, holding: lock) }
    }
}

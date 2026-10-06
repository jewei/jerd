import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct StartGateTests {
    private let messages = InstanceLock.Messages(unavailable: "Cannot lock.", busy: "Busy.")

    private func prepare(_ folder: TemporaryDirectory) throws -> (RecordLocation, InstanceLock) {
        let location = DataLayout(root: folder.url).mail.record
        try OwnedDirectory.create(location.folder)
        return (location, try InstanceLock.acquire(at: location.lockFile, messages: messages))
    }

    @Test func noRecordAllowsTheStartWhileTheLockIsHeld() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (location, lock) = try prepare(folder)
        let clearance = try StartGate().requireStopped(location, holding: lock)
        #expect(clearance.isValid)
        lock.release()
        #expect(!clearance.isValid)
    }

    @Test func theCheckRequiresTheLockOfThatRecord() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (_, lock) = try prepare(folder)
        let other = DataLayout(root: folder.url).storage.record
        #expect(throws: JerdError.invalid("Hold the lock of Storage before changing its process record.")) {
            try StartGate().requireStopped(other, holding: lock)
        }
    }

    @Test func aReusedPIDRecordIsClearedAndAStartIsAllowed() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (location, lock) = try prepare(folder)
        let current = try ProcessIdentity.capture(getpid())
        let stale = ActiveRunRecord(
            processID: getpid(), runtimeID: "old", identity: IdentityFactory.differentStart(current),
            controller: IdentityFactory.differentStart(current), gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(stale, to: location.recordFile)
        _ = try StartGate().requireStopped(location, holding: lock)
        #expect(FileProbe.presence(at: location.recordFile) == .absent)
    }

    @Test func aLiveOrLegacyLiveProcessBlocksTheStartAndKeepsTheRecord() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (location, lock) = try prepare(folder)
        let current = try ProcessIdentity.capture(getpid())
        let records = [
            ActiveRunRecord(
                processID: getpid(), runtimeID: "x", identity: current, controller: current, gracefulSignal: 15),
            ActiveRunRecord(
                processID: getpid(), runtimeID: "legacy", identity: nil, controller: nil, gracefulSignal: nil),
        ]
        for record in records {
            try ActiveRunRecordFile.write(record, to: location.recordFile)
            let bytes = contents(location.recordFile)
            #expect(
                throws: JerdError.unavailable(
                    "A previous service process needs inspection (PID \(getpid())). Open Advanced → Process recovery. "
                        + "No process was signalled.")
            ) {
                try StartGate().requireStopped(location, holding: lock)
            }
            #expect(contents(location.recordFile) == bytes)
        }
    }

    @Test func aCorruptRecordBlocksTheStartAndIsPreserved() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let (location, lock) = try prepare(folder)
        try AtomicFile.write(Data("corrupt".utf8), to: location.recordFile)
        let error = try #require(throws: JerdError.self) { try StartGate().requireStopped(location, holding: lock) }
        #expect(error.kind == .corrupt)
        #expect(contents(location.recordFile) == Data("corrupt".utf8))
    }

    @Test func anExitedLeaderWithALiveGroupMemberBlocksTheStart() async throws {
        let folder = try TemporaryDirectory(" gate tree")
        defer { folder.remove() }
        let (location, lock) = try prepare(folder)
        let supervisor = ProcessSupervisor()
        let tree = try await Fixtures.shared.executable("process-tree")
        let token = try await supervisor.start(
            ProcessRequest(executable: tree, workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("tree.log")))
        let pid = try #require(await supervisor.processID(of: token))
        let identity = try ProcessIdentity.capture(pid)
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: pid, runtimeID: "tree", identity: identity, controller: identity, gracefulSignal: 15),
            to: location.recordFile)
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
        #expect(throws: JerdError.self) { try StartGate().requireStopped(location, holding: lock) }
        #expect(await supervisor.stop(token, policy: .forceful()) == .stopped)
        _ = try StartGate().requireStopped(location, holding: lock)
        #expect(FileProbe.presence(at: location.recordFile) == .absent)
    }

    /// The check before the port checks needs no lock and changes no file.
    @Test func theReadOnlyCheckRefusesALiveRecordWithoutTheLockAndChangesNoFile() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let location = DataLayout(root: folder.url).mail.record
        try StartGate().requireNoLiveRecord(location)
        #expect(FileProbe.presence(at: location.folder) == .absent)
        try OwnedDirectory.create(location.folder)
        let current = try ProcessIdentity.capture(getpid())
        let live = ActiveRunRecord(
            processID: getpid(), runtimeID: "x", identity: current, controller: current, gracefulSignal: 15)
        try ActiveRunRecordFile.write(live, to: location.recordFile)
        let bytes = contents(location.recordFile)
        #expect(
            throws: JerdError.unavailable(
                "A previous service process needs inspection (PID \(getpid())). Open Advanced → Process recovery. "
                    + "No process was signalled.")
        ) {
            try StartGate().requireNoLiveRecord(location)
        }
        #expect(contents(location.recordFile) == bytes)
        #expect(FileProbe.presence(at: location.lockFile) == .absent)
    }

    @Test func theReadOnlyCheckKeepsAStaleRecordForTheLockedCheck() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let location = DataLayout(root: folder.url).mail.record
        try OwnedDirectory.create(location.folder)
        let current = try ProcessIdentity.capture(getpid())
        let stale = ActiveRunRecord(
            processID: getpid(), runtimeID: "old", identity: IdentityFactory.differentStart(current),
            controller: IdentityFactory.differentStart(current), gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(stale, to: location.recordFile)
        try StartGate().requireNoLiveRecord(location)
        #expect(FileProbe.presence(at: location.recordFile) != .absent)
    }
}

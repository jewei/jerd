import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct ProcessRecoveryServiceTests {
    private func mail(_ folder: TemporaryDirectory) throws -> MailLayout {
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        return mail
    }

    @Test func aReusedPIDIsClearedWithoutSignallingTheCurrentProcess() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = try mail(folder)
        let identity = try ProcessIdentity.capture(getpid())
        let record = ActiveRunRecord(
            processID: getpid(), runtimeID: "old-mail", identity: IdentityFactory.differentStart(identity),
            controller: IdentityFactory.differentStart(identity), gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(record, to: mail.activeRunFile)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        #expect(await service.inspect().first?.state == .stale)
        try await service.recover("Mail")
        #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
        #expect(identity.liveMatch() == .running)
    }

    @Test func legacyAndCorruptRecordsArePreserved() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = try mail(folder)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        for bytes in [Data("{\"processID\":\(getpid()),\"runtimeID\":\"legacy\"}".utf8), Data("corrupt".utf8)] {
            try AtomicFile.write(bytes, to: mail.activeRunFile)
            #expect(await service.inspect().first?.state == .manual)
            await #expect(throws: JerdError.self) { try await service.recover("Mail") }
            #expect(contents(mail.activeRunFile) == bytes)
        }
    }

    @Test func anUnknownOrLockedRecordIsRefused() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = try mail(folder)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        await #expect(throws: JerdError.unavailable("The process record is no longer present. Inspect again.")) {
            try await service.recover("Mail")
        }
        try AtomicFile.write(Data("{\"processID\":99999,\"runtimeID\":\"x\"}".utf8), to: mail.activeRunFile)
        let lock = try InstanceLock.acquire(at: mail.lockFile, messages: .init(unavailable: "x", busy: "y"))
        await #expect(throws: JerdError.locked("Another Jerd process is using this service.")) {
            try await service.recover("Mail")
        }
        lock.release()
    }

    @Test func aLiveControllerPreventsRecoveryAndAnEndedControllerAllowsAGracefulStop() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = try mail(folder)
        let supervisor = ProcessSupervisor()
        let token = try await supervisor.start(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("sleep.log")))
        let pid = try #require(await supervisor.processID(of: token))
        let identity = try ProcessIdentity.capture(pid)
        let controller = try ProcessIdentity.capture(getpid())
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: pid, runtimeID: "sleep", identity: identity, controller: controller, gracefulSignal: 15),
            to: mail.activeRunFile)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        #expect(await service.inspect().first?.state == .managed)
        await #expect(throws: JerdError.self) { try await service.recover("Mail") }
        #expect(await supervisor.state(of: token) == .running)
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: pid, runtimeID: "sleep", identity: identity,
                controller: IdentityFactory.differentStart(controller), gracefulSignal: 15),
            to: mail.activeRunFile)
        if AuditedSignaller.system.isSupported {
            #expect(await service.inspect().first?.state == .recoverable)
            try await service.recover("Mail", timeout: .seconds(3))
            #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
            // The kernel stops answering `proc_pidinfo` (ESRCH, which recovery reads as "exited") a
            // moment before `waitid` reports the exit, so wait for the exit before reading the state.
            #expect(await supervisor.waitForExit(of: token, timeout: .seconds(10)) == .signalled(signal: SIGTERM))
        } else {
            #expect(await service.inspect().first?.state == .manual)
        }
        _ = await supervisor.stopAll(policy: .forceful())
    }

    @Test func aFailedGroupInspectionPreservesTheRecordAndTheLiveChild() async throws {
        let folder = try TemporaryDirectory(" failed process inspection")
        defer { folder.remove() }
        let mail = try mail(folder)
        let supervisor = ProcessSupervisor()
        let binary = try await Fixtures.shared.executable("orphan-service")
        let token = try await supervisor.start(
            ProcessRequest(executable: binary, workingDirectory: folder.url),
            log: ProcessLogFile(url: folder.path("s.log")))
        let identity = try ProcessIdentity.capture(#require(await supervisor.processID(of: token)))
        let record = ActiveRunRecord(
            processID: identity.processID, runtimeID: "fixture", identity: identity,
            controller: IdentityFactory.differentStart(try ProcessIdentity.capture(getpid())), gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(record, to: mail.activeRunFile)
        let bytes = contents(mail.activeRunFile)
        let child = try #require(await waitForPID(in: folder.path("child.pid")))
        touch(folder.path("exit-master"))
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
        let failing = ProcessObserver.system.with(groups: ProcessGroupInspector(list: { _, _ in (0, EIO) }))
        let blind = ProcessRecoveryService(layout: DataLayout(root: folder.url), observer: failing)
        #expect(await blind.inspect().first?.state == .manual)
        await #expect(throws: JerdError.self) { try await blind.recover("Mail") }
        let lock = try InstanceLock.acquire(at: mail.lockFile, messages: .init(unavailable: "x", busy: "y"))
        #expect(throws: JerdError.self) { try StartGate(observer: failing).requireStopped(mail.record, holding: lock) }
        lock.release()
        #expect(contents(mail.activeRunFile) == bytes)
        #expect(kill(child, 0) == 0)
        touch(folder.path("finish-child"))
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(3))) == .stopped)
        let healthy = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        #expect(await healthy.inspect().first?.state == .stale)
        try await healthy.recover("Mail")
        #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
    }
}

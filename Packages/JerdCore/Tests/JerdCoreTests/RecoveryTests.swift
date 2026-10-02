import Foundation
import Testing
import Darwin
@testable import JerdCore

struct ProcessRecoveryTests {
    private func differentStart(_ identity: ProcessIdentity) -> ProcessIdentity {
        ProcessIdentity(processID: identity.processID, userID: identity.userID,
            startedSeconds: identity.startedSeconds + 1, startedMicroseconds: identity.startedMicroseconds,
            bootSeconds: identity.bootSeconds, executable: identity.executable, auditWords: identity.auditWords)
    }

    @Test func reusedPIDIsClearedWithoutSignallingTheCurrentProcess() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("mail")
        try PrivateFiles.directory(folder)
        let identity = try ProcessIdentity.capture(getpid())
        let record = PreviousProcessRun(processID: getpid(), runtimeID: "old-mail", identity: differentStart(identity),
            controller: differentStart(identity), gracefulSignal: SIGTERM)
        let file = folder.appendingPathComponent("active-run.json")
        try PrivateFiles.write(JSONEncoder().encode(record), to: file)
        let store = ProcessRecoveryStore(directory: root)
        #expect(try await store.inspect().first?.state == .stale)
        try await store.recover("Mail")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(identity.match() == .running)
    }

    @Test func legacyAndCorruptRecordsArePreserved() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("mail")
        try PrivateFiles.directory(folder)
        let file = folder.appendingPathComponent("active-run.json")
        let store = ProcessRecoveryStore(directory: root)
        for bytes in [Data("{\"processID\":\(getpid()),\"runtimeID\":\"legacy\"}".utf8), Data("corrupt".utf8)] {
            try PrivateFiles.write(bytes, to: file)
            #expect(try await store.inspect().first?.state == .manual)
            await #expect(throws: (any Error).self) { try await store.recover("Mail") }
            #expect(try Data(contentsOf: file) == bytes)
        }
    }

    @Test func verifiedOrphanStopsGracefullyAndLiveControllerPreventsRecovery() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("mail")
        try PrivateFiles.directory(folder)
        let file = folder.appendingPathComponent("active-run.json")
        let supervisor = ProcessSupervisor()
        let id = try await supervisor.start(ProcessRequest(executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"], directory: root), log: root.appendingPathComponent("sleep.log"))
        do {
            let pid = try #require(await supervisor.processIdentifier(id))
            try PreviousProcessRun.record(pid, runtimeID: "test-owned-sleep", at: file)
            let store = ProcessRecoveryStore(directory: root)
            #expect(try await store.inspect().first?.state == .managed)
            await #expect(throws: (any Error).self) { try await store.recover("Mail") }
            #expect(await supervisor.isRunning(id))
            let original = try PreviousProcessRun.read(file)
            let orphan = PreviousProcessRun(processID: pid, runtimeID: original.runtimeID, identity: original.identity,
                controller: differentStart(try #require(original.controller)), gracefulSignal: SIGTERM)
            try PrivateFiles.write(JSONEncoder().encode(orphan), to: file)
            if original.identity?.auditWords != nil && ProcessIdentity.supportsAuditedSignals {
                #expect(try await store.inspect().first?.state == .recoverable)
                try await store.recover("Mail", timeout: .seconds(3))
                #expect(!FileManager.default.fileExists(atPath: file.path))
                #expect(await !supervisor.isRunning(id))
            } else {
                #expect(try await store.inspect().first?.state == .manual)
            }
            await supervisor.stopAll()
        } catch { await supervisor.stopAll(); throw error }
    }

    @Test func linkedServiceDirectoryIsRejected() async throws {
        let root = try temporaryDirectory(), elsewhere = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: elsewhere) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("mail"), withDestinationURL: elsewhere)
        let store = ProcessRecoveryStore(directory: root)
        await #expect(throws: (any Error).self) { try await store.inspect() }
    }

    @Test func oversizedRecoveryPreservesThePreviousReadableRecord() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("active-run.json")
        let identity = try ProcessIdentity.capture(getpid())
        let original = PreviousProcessRun(processID: getpid(), runtimeID: "fixture", identity: identity,
            controller: identity, gracefulSignal: SIGTERM)
        try original.writeRecovery(to: file)
        let bytes = try Data(contentsOf: file)
        let largeIdentity = ProcessIdentity(processID: identity.processID, userID: identity.userID,
            startedSeconds: identity.startedSeconds, startedMicroseconds: identity.startedMicroseconds,
            bootSeconds: identity.bootSeconds, executable: String(repeating: "x", count: 131_072), auditWords: identity.auditWords)
        for children in [Array(repeating: identity, count: 1025), [largeIdentity]] {
            var oversized = original
            oversized.descendants = children
            #expect(throws: (any Error).self) { try oversized.writeRecovery(to: file) }
            #expect(try Data(contentsOf: file) == bytes)
            #expect(try PreviousProcessRun.read(file).identity == identity)
        }
    }

    @Test func failedEnumerationPreservesAnExitedMastersRecordAndLiveChild() async throws {
        let root = try temporaryDirectory(" failed process inspection")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("mail")
        try PrivateFiles.directory(folder)
        let source = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("orphan-service.c")
        let binary = root.appendingPathComponent("service")
        let built = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: [source.path, "-o", binary.path], directory: root), timeout: .seconds(20))
        #expect(built.status == 0)
        let supervisor = ProcessSupervisor()
        let token = try await supervisor.start(ProcessRequest(executable: binary, arguments: [], directory: root), log: root.appendingPathComponent("service.log"))
        do {
            let identity = try ProcessIdentity.capture(#require(await supervisor.processIdentifier(token)))
            let record = PreviousProcessRun(processID: identity.processID, runtimeID: "fixture", identity: identity,
                controller: differentStart(try ProcessIdentity.capture(getpid())), gracefulSignal: SIGTERM)
            let file = folder.appendingPathComponent("active-run.json")
            let bytes = try JSONEncoder().encode(record)
            try PrivateFiles.write(bytes, to: file)
            try PrivateFiles.write(Data(), to: root.appendingPathComponent("exit-master"))
            let deadline = ContinuousClock.now + .seconds(3)
            while await supervisor.isRunning(token), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(identity.match() == .exited)
            let childPID = try #require(Int32(String(contentsOf: root.appendingPathComponent("child.pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
            let child = try ProcessIdentity.capture(childPID)
            let failed = ProcessGroupInspector { _, _ in (0, EIO) }
            let store = ProcessRecoveryStore(directory: root, processGroups: failed)
            #expect(try await store.inspect().first?.state == .manual)
            await #expect(throws: (any Error).self) { try await store.recover("Mail") }
            #expect(throws: (any Error).self) { try PreviousProcessRun.requireStopped(at: file, processGroups: failed) }
            #expect(try Data(contentsOf: file) == bytes)
            #expect(child.match() == .running)
            try PrivateFiles.write(Data(), to: root.appendingPathComponent("finish-child"))
            #expect(await supervisor.stopGracefully(token, timeout: .seconds(3)))
            #expect(try await ProcessRecoveryStore(directory: root).inspect().first?.state == .stale)
            try await ProcessRecoveryStore(directory: root).recover("Mail")
            #expect(!FileManager.default.fileExists(atPath: file.path))
        } catch {
            try? PrivateFiles.write(Data(), to: root.appendingPathComponent("finish-child"))
            _ = await supervisor.stopGracefully(token, timeout: .seconds(3))
            throw error
        }
    }
}

struct BackupRetentionTests {
    @Test(arguments: [false, true])
    func pendingRecoveryProtectsEveryBackupAndExplicitCleanupKeepsCurrentData(pending: Bool) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = root.appendingPathComponent("storage"), id = UUID().uuidString, other = UUID().uuidString
        let folder = service.appendingPathComponent("runtime-backups/\(id)")
        let otherFolder = service.appendingPathComponent("runtime-backups/\(other)")
        try PrivateFiles.directory(folder); try PrivateFiles.directory(otherFolder)
        let current = service.appendingPathComponent("data")
        try PrivateFiles.directory(current)
        let bytes = Data("retained-object".utf8)
        for file in [folder.appendingPathComponent("object"), otherFolder.appendingPathComponent("object"), current.appendingPathComponent("object")] {
            try PrivateFiles.write(bytes, to: file)
        }
        if pending { try PrivateFiles.write(Data("corrupt pending recovery".utf8), to: service.appendingPathComponent("runtime-update.json")) }
        let store = BackupRetentionStore(directory: root)
        let backups = try await store.inspect()
        #expect(backups.count == 2)
        #expect(backups.allSatisfy { $0.bytes == Int64(bytes.count) && $0.isProtected == pending })
        if pending {
            await #expect(throws: (any Error).self) { try await store.remove("storage/\(id)") }
            #expect(try Data(contentsOf: folder.appendingPathComponent("object")) == bytes)
        } else { try await store.remove("storage/\(id)") }
        #expect(try Data(contentsOf: otherFolder.appendingPathComponent("object")) == bytes)
        #expect(try Data(contentsOf: current.appendingPathComponent("object")) == bytes)
        await #expect(throws: (any Error).self) { try await store.remove("storage/../../data") }
    }

    @Test func activeServiceAndLinkedBackupPreventDeletion() async throws {
        let root = try temporaryDirectory(), elsewhere = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: elsewhere) }
        let service = root.appendingPathComponent("mail"), id = UUID().uuidString
        let folder = service.appendingPathComponent("runtime-backups/\(id)")
        try PrivateFiles.directory(folder)
        let lock = open(service.appendingPathComponent("service.lock").path, O_RDWR | O_CREAT, 0o600)
        #expect(lock >= 0)
        defer { close(lock) }
        #expect(flock(lock, LOCK_EX | LOCK_NB) == 0)
        let store = BackupRetentionStore(directory: root)
        await #expect(throws: (any Error).self) { try await store.remove("mail/\(id)") }
        _ = flock(lock, LOCK_UN)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: elsewhere)
        #expect(try await store.inspect().first?.isProtected == true)
        await #expect(throws: (any Error).self) { try await store.remove("mail/\(id)") }
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
    }
}

struct ControllerExitRecoveryTests {
    @Test(.enabled(if: ProcessIdentity.supportsAuditedSignals))
    func separateControllerExitLeavesARecoverableService() async throws {
        let root = try temporaryDirectory(" controller exit")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("mail")
        try PrivateFiles.directory(folder)
        let source = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("orphan-controller.c")
        let binary = root.appendingPathComponent("controller")
        let built = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: [source.path, "-o", binary.path], directory: root), timeout: .seconds(20))
        #expect(built.status == 0)
        let supervisor = ProcessSupervisor(), log = root.appendingPathComponent("controller.log")
        let token = try await supervisor.start(ProcessRequest(executable: binary, arguments: [], directory: root), log: log)
        var child: ProcessIdentity?
        do {
            let controller = try ProcessIdentity.capture(#require(await supervisor.processIdentifier(token)))
            let deadline = ContinuousClock.now + .seconds(3)
            var pid: Int32?
            while pid == nil, ContinuousClock.now < deadline {
                pid = Int32(try String(contentsOf: log, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
                if pid == nil { try await Task.sleep(for: .milliseconds(10)) }
            }
            let identity = try ProcessIdentity.capture(#require(pid)); child = identity
            let record = PreviousProcessRun(processID: identity.processID, runtimeID: "isolated-service",
                identity: identity, controller: controller, gracefulSignal: SIGTERM)
            let file = folder.appendingPathComponent("active-run.json")
            try PrivateFiles.write(JSONEncoder().encode(record), to: file)
            await supervisor.stop(token)
            #expect(controller.match() == .exited)
            #expect(identity.match() == .running)
            let restarted = ProcessRecoveryStore(directory: root)
            #expect(try await restarted.inspect().first?.state == .recoverable)
            try await restarted.recover("Mail", timeout: .seconds(3))
            #expect(identity.match() == .exited)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        } catch {
            if let child, child.match() == .running { try? child.signalGracefully(SIGTERM) }
            await supervisor.stopAll()
            throw error
        }
    }

    @Test func anExitedOwnedMasterStillGetsAConservativeRecord() async throws {
        let root = try temporaryDirectory(" early master exit")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("orphan-service.c")
        let binary = root.appendingPathComponent("service")
        let built = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/clang"),
            arguments: [source.path, "-o", binary.path], directory: root), timeout: .seconds(20))
        #expect(built.status == 0)
        try PrivateFiles.write(Data(), to: root.appendingPathComponent("exit-master"))
        let supervisor = ProcessSupervisor(gracefulTimeout: .milliseconds(100))
        let token = try await supervisor.start(ProcessRequest(executable: binary, arguments: [], directory: root), log: root.appendingPathComponent("service.log"))
        do {
            let deadline = ContinuousClock.now + .seconds(3)
            while await supervisor.isRunning(token), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(await supervisor.processIdentifier(token) == nil)
            let pid = try #require(await supervisor.ownedProcessIdentifier(token))
            let record = root.appendingPathComponent("active-run.json")
            #expect(throws: (any Error).self) { try PreviousProcessRun.record(pid, runtimeID: "fixture", at: record) }
            #expect(try PreviousProcessRun.read(record).identity == nil)
            #expect(await !supervisor.stopGracefully(token))
            #expect(throws: (any Error).self) { try PreviousProcessRun.requireStopped(at: record) }
            try PrivateFiles.write(Data(), to: root.appendingPathComponent("finish-child"))
            try await Task.sleep(for: .milliseconds(50))
            #expect(await supervisor.stopGracefully(token))
            try PreviousProcessRun.requireStopped(at: record)
        } catch {
            try? PrivateFiles.write(Data(), to: root.appendingPathComponent("finish-child"))
            try? await Task.sleep(for: .milliseconds(50))
            _ = await supervisor.stopGracefully(token)
            throw error
        }
    }
}

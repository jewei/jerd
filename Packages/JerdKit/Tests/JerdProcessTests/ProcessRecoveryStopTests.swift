import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@Suite(.enabled(if: AuditedSignaller.system.isSupported))
struct ProcessRecoveryStopTests {
    private func start(
        _ fixture: String, _ arguments: [String] = [], in folder: TemporaryDirectory,
        using supervisor: ProcessSupervisor
    )
        async throws -> ProcessToken
    {
        let binary = try await Fixtures.shared.executable(fixture)
        let request = ProcessRequest(executable: binary, arguments: arguments, workingDirectory: folder.url)
        return try await supervisor.start(request, log: ProcessLogFile(url: folder.path("\(fixture).log")))
    }

    @Test func aServiceLeftByAnEndedControllerIsRecoverable() async throws {
        let folder = try TemporaryDirectory(" controller exit")
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor()
        let token = try await start("orphan-controller", in: folder, using: supervisor)
        let controller = try ProcessIdentity.capture(#require(await supervisor.processID(of: token)))
        #expect(
            await eventually {
                pid_t(text(folder.path("orphan-controller.log")).trimmingCharacters(in: .newlines)) != nil
            })
        let childPID = try #require(pid_t(text(folder.path("orphan-controller.log")).trimmingCharacters(in: .newlines)))
        let child = try ProcessIdentity.capture(childPID)
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: childPID, runtimeID: "isolated", identity: child, controller: controller, gracefulSignal: 15),
            to: mail.activeRunFile)
        // The controller ends on its own. A supervisor stop would also stop its escaped child.
        kill(controller.processID, SIGTERM)
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(5)) == .signalled(signal: SIGTERM))
        #expect(controller.liveMatch() == .exited)
        #expect(child.liveMatch() == .running)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        #expect(await service.inspect().first?.state == .recoverable)
        try await service.recover("Mail", timeout: .seconds(3))
        #expect(child.liveMatch() != .running)
        #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
        #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
    }

    @Test func savedDescendantsReceiveTheRecordedSignal() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor()
        let token = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await eventually { text(folder.path("graceful-process.log")) == "ready\n" })
        let descendant = try ProcessIdentity.capture(#require(await supervisor.processID(of: token)))
        let current = try ProcessIdentity.capture(getpid())
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: getpid(), runtimeID: "pg", identity: IdentityFactory.differentStart(current),
                controller: IdentityFactory.differentStart(current), gracefulSignal: SIGINT, descendants: [descendant]),
            to: mail.activeRunFile)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        #expect(await service.inspect().first?.state == .recoverable)
        try await service.recover("Mail", timeout: .seconds(3))
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
        #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
    }

    /// A paused orphan keeps the caught signal pending, so recovery continues it after the signal.
    @Test func aPausedOrphanIsContinuedSoThatItStops() async throws {
        let folder = try TemporaryDirectory(" paused orphan")
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor()
        let token = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await eventually { text(folder.path("graceful-process.log")) == "ready\n" })
        let pid = try #require(await supervisor.processID(of: token))
        let identity = try ProcessIdentity.capture(pid)
        let controller = IdentityFactory.differentStart(try ProcessIdentity.capture(getpid()))
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: pid, runtimeID: "paused", identity: identity, controller: controller,
                gracefulSignal: SIGINT),
            to: mail.activeRunFile)
        #expect(await ProcessPause.pause(pid))
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url), pollInterval: .milliseconds(20))
        #expect(await service.inspect().first?.state == .recoverable)
        try await service.recover("Mail", timeout: .seconds(3))
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
        #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
        #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
    }

    /// A paused group whose leader waits for its worker, like a database server and its backend.
    /// Recovery continues the worker too, so the leader can end it and stop.
    @Test func recoveryContinuesEveryPausedMemberOfARunningLeader() async throws {
        let folder = try TemporaryDirectory(" paused group")
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor(ceiling: .forceful)
        let token = try await start("group-with-worker", in: folder, using: supervisor)
        let log = folder.path("group-with-worker.log")
        #expect(await eventually { pid_t(text(log).trimmingCharacters(in: .newlines)) != nil })
        let worker = try #require(pid_t(text(log).trimmingCharacters(in: .newlines)))
        let leader = try #require(await supervisor.processID(of: token))
        do {
            try ActiveRunRecordFile.write(
                ActiveRunRecord(
                    processID: leader, runtimeID: "group", identity: try ProcessIdentity.capture(leader),
                    controller: IdentityFactory.differentStart(try ProcessIdentity.capture(getpid())),
                    gracefulSignal: SIGINT),
                to: mail.activeRunFile)
            // The worker is a child of the leader, which stays unreaped while the test runs.
            #expect(await ProcessPause.pause(worker))
            #expect(await ProcessPause.pause(leader))
            let service = ProcessRecoveryService(layout: DataLayout(root: folder.url), pollInterval: .milliseconds(20))
            try await service.recover("Mail", timeout: .seconds(3))
            #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
            #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
            #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
        } catch {
            _ = await supervisor.stop(token, policy: .forceful(leaderTimeout: .milliseconds(50)))
            throw error
        }
    }

    /// A saved descendant of an exited leader that is paused gets the signal and then `SIGCONT`.
    @Test func recoveryContinuesAPausedSavedDescendantOfAnExitedLeader() async throws {
        let folder = try TemporaryDirectory(" paused descendant")
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor(ceiling: .forceful)
        let token = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await eventually { text(folder.path("graceful-process.log")) == "ready\n" })
        let pid = try #require(await supervisor.processID(of: token))
        do {
            let current = try ProcessIdentity.capture(getpid())
            try ActiveRunRecordFile.write(
                ActiveRunRecord(
                    processID: getpid(), runtimeID: "pg", identity: IdentityFactory.differentStart(current),
                    controller: IdentityFactory.differentStart(current), gracefulSignal: SIGINT,
                    descendants: [try ProcessIdentity.capture(pid)]),
                to: mail.activeRunFile)
            #expect(await ProcessPause.pause(pid))
            let service = ProcessRecoveryService(layout: DataLayout(root: folder.url), pollInterval: .milliseconds(20))
            try await service.recover("Mail", timeout: .seconds(3))
            #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
            #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
            #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
        } catch {
            _ = await supervisor.stop(token, policy: .forceful(leaderTimeout: .milliseconds(50)))
            throw error
        }
    }

    @Test func aProcessThatIgnoresTheSignalTimesOutKeepsItsRecordAndBlocksASecondRecovery() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor(ceiling: .forceful)
        let token = try await start("sleeper", ["ignore-term"], in: folder, using: supervisor)
        let pid = try #require(await waitForPID(in: folder.path("sleeper.pid")))
        let identity = try ProcessIdentity.capture(pid)
        let controller = IdentityFactory.differentStart(try ProcessIdentity.capture(getpid()))
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: pid, runtimeID: "stubborn", identity: identity, controller: controller, gracefulSignal: 15),
            to: mail.activeRunFile)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url), pollInterval: .milliseconds(20))
        let first = Task { try await service.recover("Mail", timeout: .milliseconds(400)) }
        try await Task.sleep(for: .milliseconds(100))
        await #expect(throws: JerdError.unavailable("Wait for process recovery to finish.")) {
            try await service.recover("Mail")
        }
        await #expect(
            throws: JerdError.unavailable(
                "The service has not stopped safely. Its process record and data were preserved. Retry recovery after checking its log."
            )
        ) {
            try await first.value
        }
        let saved = try ActiveRunRecordFile.read(mail.activeRunFile)
        #expect(saved.descendants == [])
        #expect(await supervisor.state(of: token) == .running)
        #expect(await supervisor.stop(token, policy: .forceful(leaderTimeout: .milliseconds(50))) == .stopped)
    }
}

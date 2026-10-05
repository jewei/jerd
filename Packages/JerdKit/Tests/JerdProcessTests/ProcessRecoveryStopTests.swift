import Darwin
import Foundation
import JerdFoundation
import JerdProcess
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
        #expect(await supervisor.stop(token, policy: .forceful()) == .stopped)
        #expect(controller.liveMatch() == .exited)
        #expect(child.liveMatch() == .running)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url))
        #expect(await service.inspect().first?.state == .recoverable)
        try await service.recover("Mail", timeout: .seconds(3))
        #expect(child.liveMatch() != .running)
        #expect(FileProbe.presence(at: mail.activeRunFile) == .absent)
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

    @Test func aProcessThatIgnoresTheSignalTimesOutKeepsItsRecordAndBlocksASecondRecovery() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor()
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

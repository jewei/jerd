import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

/// Regression test: a descendant that calls `setsid` is found by its parent chain.
@Suite struct EscapedDescendantTests {
    private func startController(
        _ arguments: [String] = [], in folder: TemporaryDirectory, using supervisor: ProcessSupervisor
    ) async throws -> (ProcessToken, pid_t) {
        let binary = try await Fixtures.shared.executable("orphan-controller")
        let request = ProcessRequest(executable: binary, arguments: arguments, workingDirectory: folder.url)
        let log = folder.path("orphan-controller.log")
        let token = try await supervisor.start(request, log: ProcessLogFile(url: log))
        #expect(await eventually { pid_t(text(log).trimmingCharacters(in: .newlines)) != nil })
        return (token, try #require(pid_t(text(log).trimmingCharacters(in: .newlines))))
    }

    @Test func aChildThatLeftTheGroupIsStoppedWithTheGroup() async throws {
        let folder = try TemporaryDirectory(" escaped child")
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let (token, child) = try await startController(in: folder, using: supervisor)
        #expect(getpgid(child) == child)  // The child leads its own session and group.
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(3))) == .stopped)
        #expect(await eventually { isGone(child) })
    }

    @Test func aChildThatLeftTheGroupAndIgnoresTheSignalBlocksStopped() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let (token, child) = try await startController(["stubborn-child"], in: folder, using: supervisor)
        let outcome = await supervisor.stop(token, policy: .graceful(timeout: .milliseconds(300)))
        #expect(outcome == .timedOut(leaderRunning: false))
        #expect(kill(child, 0) == 0)
        #expect(await supervisor.processID(of: token) != nil)
        kill(child, SIGKILL)
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(3))) == .stopped)
    }

    @Test(.enabled(if: AuditedSignaller.system.isSupported))
    func recoverySavesAChildThatLeftTheGroupAndTheStartGateWaitsForIt() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let mail = DataLayout(root: folder.url).mail
        try OwnedDirectory.create(mail.root)
        let supervisor = ProcessSupervisor()
        let (token, child) = try await startController(in: folder, using: supervisor)
        let leader = try ProcessIdentity.capture(#require(await supervisor.processID(of: token)))
        let controller = IdentityFactory.differentStart(try ProcessIdentity.capture(getpid()))
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: leader.processID, runtimeID: "service", identity: leader, controller: controller,
                gracefulSignal: SIGTERM),
            to: mail.activeRunFile)
        let service = ProcessRecoveryService(layout: DataLayout(root: folder.url), pollInterval: .milliseconds(20))
        // The leader stops, but the child outside its group runs on: the record keeps it.
        await #expect(throws: JerdError.self) { try await service.recover("Mail", timeout: .milliseconds(500)) }
        let saved = try ActiveRunRecordFile.read(mail.activeRunFile)
        #expect(saved.descendants?.map(\.processID) == [child])
        let lock = try InstanceLock.acquire(at: mail.lockFile, messages: .init(unavailable: "u", busy: "b"))
        #expect(throws: JerdError.self) { try StartGate().requireStopped(mail.record, holding: lock) }
        lock.release()
        // A second attempt signals the saved child with the recorded signal.
        try await service.recover("Mail", timeout: .seconds(3))
        #expect(await eventually { isGone(child) })
        #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
    }
}

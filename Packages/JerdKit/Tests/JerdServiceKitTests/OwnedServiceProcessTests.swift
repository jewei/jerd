import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

/// Real child processes from the C fixtures, with a real supervisor and fake `lsof`.
@Suite struct OwnedServiceProcessTests {
    private struct Setup {
        let directory: TemporaryDirectory
        let folder: URL
        let supervisor = ProcessSupervisor()

        init() throws {
            directory = try TemporaryDirectory(" owned process ü")
            folder = directory.path("instance")
        }

        func instance(executable: URL, signal: Int32, initializer: InitializerPlan? = nil) -> ManagedInstance {
            let lsof = PIDLsof(ports: [41_002])
            let commands = ScriptedCommands { request in
                if request.executable.lastPathComponent == "lsof" { return lsof.answer(request.arguments) }
                return CommandResult(status: 0, output: "fixture 1.0.0")
            }
            let probe = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })
            let effects = ServiceEffects(
                processes: supervisor, commands: commands, ports: LoopbackPortGuard(commands: commands, probe: probe),
                stopTimeout: .milliseconds(300))
            var definition = definition(executable, signal)
            definition.initializer = initializer
            return ManagedInstance(definition: definition, effects: effects)
        }

        private func definition(_ executable: URL, _ signal: Int32) -> FakeServiceDefinition {
            let record = RecordLocation(
                family: .database, instance: UUID(), recordFile: folder.appendingPathComponent("active-run.json"),
                lockFile: folder.appendingPathComponent("service.lock"))
            let logFile = folder.appendingPathComponent("server.log")
            let log = ServiceLog(file: logFile, previousFile: folder.appendingPathComponent("server.previous.log"))
            let profile = ServiceProfile(
                name: "Fixture", runtimeID: "fixture", record: record, containingDirectory: directory.url, log: log,
                ports: [41_002], stopSignal: signal, messages: FakeServiceDefinition.messages)
            let readiness = ReadinessCheck(
                deadline: .seconds(5), interval: .milliseconds(10), initialFailure: "No output.",
                timeoutMessage: "The fixture timed out.", timeoutDetail: .logTail,
                probe: { text(logFile).contains("ready") ? .ready : .notReady("waiting") })
            let request = ProcessRequest(executable: executable, workingDirectory: folder)
            return FakeServiceDefinition(
                profile: profile,
                versionProbe: VersionProbe(
                    request: ProcessRequest(executable: executable, arguments: ["--version"], workingDirectory: folder),
                    rule: .standalone(version: "1.0.0"), mismatchMessage: "Mismatch."),
                plan: LaunchPlan(request: request, ports: [41_002], readiness: readiness), events: EventLog())
        }
    }

    @Test func anExitedMasterKeepsTheDataLockedUntilItsChildStops() async throws {
        let setup = try Setup()
        defer { setup.directory.remove() }
        let instance = setup.instance(
            executable: try await Fixtures.shared.executable("orphan-service"), signal: SIGTERM)
        do {
            try await instance.start()
            let pid = try #require(await instance.processID)
            let record = try #require(contents(setup.folder.appendingPathComponent("active-run.json")))
            FileManager.default.createFile(
                atPath: setup.folder.appendingPathComponent("exit-master").path, contents: nil)
            #expect(await eventually { await instance.refresh() != .running(pid: pid) })
            await instance.waitForPendingStop()
            guard case .stuck(let stuckPID, let reason) = await instance.state else {
                throw JerdError.invalid("Expected a stuck instance, got \(await instance.state)")
            }
            #expect(stuckPID == pid)
            #expect(reason.hasSuffix(ServiceMessages.childStillRunning))
            #expect(contents(setup.folder.appendingPathComponent("active-run.json")) == record)
            #expect(!isLockFree(setup.folder.appendingPathComponent("service.lock")))
            await #expect(throws: (any Error).self) { try await instance.start() }
            FileManager.default.createFile(
                atPath: setup.folder.appendingPathComponent("finish-child").path, contents: nil)
            try await Task.sleep(for: .milliseconds(100))
            try await instance.stop()
            #expect(await instance.state == .stopped)
            #expect(!exists(setup.folder.appendingPathComponent("active-run.json")))
        } catch {
            FileManager.default.createFile(
                atPath: setup.folder.appendingPathComponent("finish-child").path, contents: nil)
            _ = await setup.supervisor.stopAll(policy: .forceful())
            throw error
        }
    }

    @Test func aTimedOutInitializerThatIgnoresSIGTERMStaysOwnedLockedAndRecorded() async throws {
        let setup = try Setup()
        defer { setup.directory.remove() }
        let fixture = try await Fixtures.shared.executable("graceful-process")
        // The limit leaves time for the first launch of a new binary, so that the fixture
        // ignores SIGTERM before the stop sends it.
        let initializer = InitializerPlan(
            request: ProcessRequest(executable: fixture, workingDirectory: setup.folder), timeout: .seconds(2),
            timeoutMessage: "The fixture initializer timed out.")
        let instance = setup.instance(executable: fixture, signal: SIGTERM, initializer: initializer)
        await #expect(throws: (any Error).self) { try await instance.start() }
        // The process stays owned (not reaped), so its PID cannot be reused before the Stop.
        let pid = try #require(await instance.processID)
        guard case .stuck(pid, let reason) = await instance.state else {
            kill(pid, SIGINT)
            Issue.record("Expected a stuck initializer, got \(await instance.state)")
            return
        }
        #expect(reason.hasPrefix("The fixture initializer timed out. Fixture did not stop within"))
        #expect(kill(pid, 0) == 0)
        let record = setup.folder.appendingPathComponent("active-run.json")
        #expect(try ActiveRunRecordFile.read(record).processID == pid)
        #expect(!isLockFree(setup.folder.appendingPathComponent("service.lock")))
        // The fixture ends on SIGINT. A Stop then releases the lock and the record.
        kill(pid, SIGINT)
        try await instance.stop()
        #expect(await instance.state == .stopped)
        #expect(!exists(record))
        #expect(isLockFree(setup.folder.appendingPathComponent("service.lock")))
    }

    @Test func aGracefulTimeoutKeepsTheProcessAliveAndOwned() async throws {
        let setup = try Setup()
        defer { setup.directory.remove() }
        let instance = setup.instance(
            executable: try await Fixtures.shared.executable("graceful-process"), signal: SIGTERM)
        try await instance.start()
        let pid = try #require(await instance.processID)
        await #expect(throws: (any Error).self) { try await instance.stop() }
        #expect(await instance.state.processID == pid)
        #expect(kill(pid, 0) == 0)
        // The fixture ignores SIGTERM and ends on SIGINT. A retry then stops it.
        kill(pid, SIGINT)
        try await instance.stop()
        #expect(await instance.state == .stopped)
    }

    /// A paused server (`kill -STOP`, a debugger) is alive: it keeps its state, and Stop continues it.
    @Test func aPausedServiceStaysRunningAndStopsGracefully() async throws {
        let setup = try Setup()
        defer { setup.directory.remove() }
        let instance = setup.instance(
            executable: try await Fixtures.shared.executable("graceful-process"), signal: SIGINT)
        try await instance.start()
        let pid = try #require(await instance.processID)
        #expect(await ProcessPause.pause(pid))
        #expect(await instance.refresh() == .running(pid: pid))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await instance.refresh() == .running(pid: pid))
        try await instance.stop()
        #expect(await instance.state == .stopped)
        #expect(kill(pid, 0) == -1)
        #expect(!exists(setup.folder.appendingPathComponent("active-run.json")))
        #expect(isLockFree(setup.folder.appendingPathComponent("service.lock")))
    }

    /// A paused server that ignores the stop signal after it continues is stuck: Jerd keeps the
    /// process, its record, and its lock, and the stop fails (which cancels Quit).
    @Test func aPausedServiceThatDoesNotStopStaysStuckWithItsRecordAndLock() async throws {
        let setup = try Setup()
        defer { setup.directory.remove() }
        let instance = setup.instance(
            executable: try await Fixtures.shared.executable("graceful-process"), signal: SIGTERM)
        try await instance.start()
        let pid = try #require(await instance.processID)
        let record = setup.folder.appendingPathComponent("active-run.json")
        let saved = try #require(contents(record))
        #expect(await ProcessPause.pause(pid))
        await #expect(throws: (any Error).self) { try await instance.stop() }
        guard case .stuck(pid, _) = await instance.state else {
            kill(pid, SIGINT)
            Issue.record("Expected a stuck service, got \(await instance.state)")
            return
        }
        #expect(kill(pid, 0) == 0)
        #expect(!ProcessPause.isPaused(pid))
        #expect(contents(record) == saved)
        #expect(!isLockFree(setup.folder.appendingPathComponent("service.lock")))
        kill(pid, SIGINT)
        try await instance.stop()
        #expect(await instance.state == .stopped)
    }
}

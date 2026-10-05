import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
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

        func instance(executable: URL, signal: Int32) -> ManagedInstance {
            let lsof = PIDLsof(ports: [41_002])
            let commands = ScriptedCommands { request in
                if request.executable.lastPathComponent == "lsof" { return lsof.answer(request.arguments) }
                return CommandResult(status: 0, output: "fixture 1.0.0")
            }
            let probe = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })
            let effects = ServiceEffects(
                processes: supervisor, commands: commands, ports: LoopbackPortGuard(commands: commands, probe: probe),
                stopTimeout: .milliseconds(300))
            return ManagedInstance(definition: definition(executable, signal), effects: effects)
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
}

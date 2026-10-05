import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

@Suite struct EngineRunnerStartTests {
    @Test func aStartWritesFilesValidatesRecordsAndStartsCaddyLast() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let plan = try harness.plan()
        _ = try await harness.start(plan, layout: layout)
        #expect(await harness.engine.state == .running)
        let requests = await harness.processes.requests
        #expect(requests.map(\.arguments.first) == ["-c", "run"])
        #expect(requests[0].arguments.last == "-F")
        #expect(requests[1].arguments == ["run", "--config", layout.environment.caddyConfigurationFile.path])
        #expect(requests[1].listeners != nil && requests[1].environment == layout.processEnvironment)
        let validations = harness.commands.arguments.filter { $0.last == "-t" || $0.first == "validate" }
        #expect(validations.count == 2)
        let pool = layout.pool(runtimeID: Samples.runtimeID, index: 0)
        #expect(text(pool.fpmConfigurationFile).contains("listen = \"\(pool.socket.path)\""))
        #expect(text(pool.phpINIFile) == PHPIniPolicy.fpm)
        #expect(mode(layout.socketDirectory) == 0o700)
        let names = try FileManager.default.contentsOfDirectory(atPath: layout.environment.processesDirectory.path)
        #expect(names.filter { $0.hasSuffix(".json") }.count == 2)
        #expect(throws: JerdError.self) {
            try InstanceLock.acquire(at: layout.environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
        }
        await harness.engine.stop()
        #expect(await harness.engine.state == .stopped)
        #expect(await harness.processes.stopSignals == [SIGTERM, SIGQUIT])
        #expect(isAbsent(layout.socketDirectory))
        let left = try FileManager.default.contentsOfDirectory(atPath: layout.environment.processesDirectory.path)
        #expect(left == ["recovery.lock"])
    }

    @Test func twoRuntimesGetTwoPoolsKeyedByRuntimeID() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let second = Samples.runtime(cli: "/local/php-b", fpm: "/local/php-fpm-b")
        let plan = try harness.plan(
            ["a.test", "b.test", "c.test"], runtimes: [Samples.runtime(id: Samples.runtimeID), second])
        _ = try await harness.start(plan, layout: layout)
        let launches = await harness.processes.requests.filter { $0.arguments.last == "-F" }
        #expect(launches.map(\.executable.path) == ["/local/php-fpm", "/local/php-fpm-b"])
        #expect(launches[1].arguments[3] == layout.pool(runtimeID: second.id, index: 1).fpmConfigurationFile.path)
        let caddy = text(layout.environment.caddyConfigurationFile)
        #expect(caddy.contains("php-0.sock") && caddy.contains("php-1.sock"))
        await harness.engine.stop()
    }

    @Test func aCaddyLaunchFailureStopsFPMAndRemovesTheOwnedSocketFolder() async throws {
        let harness = try EngineHarness(processes: FakeProcesses(failLaunch: { $0.arguments.first == "run" }))
        defer { harness.remove() }
        let layout = try harness.layout()
        await #expect(throws: JerdError.processFailed("Injected launch failure")) {
            try await harness.start(try harness.plan(), layout: layout)
        }
        #expect(await harness.processes.allStopped)
        #expect(await harness.processes.startCount == 1)
        #expect(isAbsent(layout.socketDirectory))
        #expect(await harness.engine.state == .failed("Injected launch failure"))
    }

    @Test func aSilentFPMFailsTheStartBeforeCaddy() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        harness.pinger.fail(true)
        let layout = try harness.layout()
        await #expect(throws: JerdError.self) { try await harness.start(try harness.plan(), layout: layout) }
        #expect(await harness.processes.startCount == 1)
        #expect(await harness.processes.allStopped)
        #expect(isAbsent(layout.socketDirectory))
    }

    @Test func anUnknownSocketFolderIsPreservedAndNothingStarts() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        try FileManager.default.createDirectory(at: layout.socketDirectory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: layout.socketDirectory) }
        let marker = layout.socketDirectory.appendingPathComponent("keep")
        try Data("owned elsewhere".utf8).write(to: marker)
        await #expect(
            throws: JerdError.processFailed(
                "The socket directory already exists. Use a new private run directory; do not remove an unknown socket."
            )
        ) { try await harness.start(try harness.plan(), layout: layout) }
        #expect(await harness.processes.startCount == 0)
        #expect(text(marker) == "owned elsewhere")
    }

    @Test(arguments: ["-t", "validate"])
    func aFailedValidationStopsBeforeAnyLaunch(_ failing: String) async throws {
        let harness = try EngineHarness(failing: failing)
        defer { harness.remove() }
        let layout = try harness.layout()
        await #expect(throws: JerdError.processFailed("Configuration validation failed: \(failing) failed")) {
            try await harness.start(try harness.plan(), layout: layout)
        }
        #expect(await harness.processes.startCount == 0)
        #expect(isAbsent(layout.socketDirectory))
    }

    @Test func aLivePreviousRecordBlocksAndAStaleOneIsRemoved() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let live = layout.environment.processRecord(UUID())
        let stale = layout.environment.processRecord(UUID())
        try OwnedDirectory.create(layout.environment.processesDirectory)
        try write(record: 4_242, to: live.recordFile)
        try write(record: 4_343, to: stale.recordFile)
        _ = harness.processes.live.withLock { $0.insert(4_242) }
        await #expect(throws: JerdError.self) { try await harness.start(try harness.plan(), layout: layout) }
        #expect(await harness.processes.startCount == 0)
        #expect(!isAbsent(live.recordFile))
        _ = harness.processes.live.withLock { $0.remove(4_242) }
        _ = try await harness.start(try harness.plan(), layout: try harness.layout())
        #expect(isAbsent(live.recordFile) && isAbsent(stale.recordFile))
        await harness.engine.stop()
    }

    @Test func anotherSessionHoldingTheEnvironmentLockBlocksTheStart() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        try OwnedDirectory.create(layout.environment.processesDirectory)
        let lock = try InstanceLock.acquire(
            at: layout.environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
        defer { lock.release() }
        await #expect(throws: JerdError.locked("Another Jerd session is using this web environment.")) {
            try await harness.start(try harness.plan(), layout: layout)
        }
        #expect(await harness.processes.startCount == 0)
    }

    private func write(record pid: pid_t, to file: URL) throws {
        let identity = ProcessIdentity(
            processID: pid, userID: geteuid(), startedSeconds: 1, startedMicroseconds: 0, bootSeconds: 0,
            executable: "/fake", auditWords: [1, 2, 3, 4, 5, 6, 7, 8], bootSessionID: "TEST")
        try ActiveRunRecordFile.write(
            ActiveRunRecord(
                processID: pid, runtimeID: "PHP 8.4.0", identity: identity, controller: identity,
                gracefulSignal: SIGQUIT),
            to: file)
    }
}

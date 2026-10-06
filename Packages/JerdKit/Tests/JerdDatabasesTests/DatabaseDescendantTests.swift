import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing
import os

@testable import JerdDatabases

/// A real child (`Fixtures/orphan-service.c` as `redis-server`) whose master exits and leaves a
/// child that ignores SIGTERM. Commands are fake: `lsof` reports the child as the owner.
@Suite struct DatabaseDescendantTests {
    private static func commands() -> ScriptedCommands {
        let owner = OSAllocatedUnfairLock<pid_t?>(initialState: nil)
        return ScriptedCommands { request in
            let arguments = request.arguments
            switch request.executable.lastPathComponent {
            case "redis-server": return CommandResult(status: 0, output: "Redis server v=8.8.3 sha=0")
            case "redis-cli": return CommandResult(status: 0, output: "PONG\n")
            default: break
            }
            if arguments.contains("-iUDP") { return CommandResult(status: 1, output: "") }
            if let index = arguments.firstIndex(of: "-p"), let pid = pid_t(arguments[index + 1]) {
                owner.withLock { $0 = pid }
                return CommandResult(status: 0, output: "p\(pid)\nn127.0.0.1:26700\n")
            }
            guard let pid = owner.withLock({ $0 }) else { return CommandResult(status: 1, output: "") }
            return CommandResult(status: 0, output: "p\(pid)\n")
        }
    }

    /// A loaded manager whose Redis runtime is a C fixture (the orphan-service fixture by default),
    /// with one service.
    private static func fixtureManager(
        _ directory: TemporaryDirectory, layout: DatabasesLayout, supervisor: ProcessSupervisor,
        fixture: String = "orphan-service"
    ) async throws -> (DatabaseManager, DatabaseService) {
        let runtimeFolder = directory.path("runtime")
        try OwnedDirectory.create(runtimeFolder.appendingPathComponent("bin"))
        try FileManager.default.copyItem(
            at: try await Fixtures.shared.executable(fixture),
            to: runtimeFolder.appendingPathComponent("bin/redis-server"))
        let commands = Self.commands()
        let probe = LoopbackProbe(isAccepting: { _ in false }, requireBindable: { _ in })
        let effects = ServiceEffects(
            processes: supervisor, commands: commands, ports: LoopbackPortGuard(commands: commands, probe: probe),
            stopTimeout: .milliseconds(300))
        let manager = DatabaseManager(layout: layout, effects: effects)
        _ = try await manager.load()
        let runtime = DatabaseRuntime(id: "fixture", engine: .redis, version: "8.8.3", path: runtimeFolder.path)
        try await manager.registerRuntimes([runtime])
        let service = try await manager.add(name: "Fixture", runtimeID: runtime.id, port: 26_700)
        return (manager, service)
    }

    @Test func anExitedMasterKeepsDataLockedUntilItsChildStops() async throws {
        let directory = try TemporaryDirectory(" owned descendants")
        defer { directory.remove() }
        let supervisor = ProcessSupervisor()
        let layout = DataLayout(root: directory.path("Jerd")).databases
        let (manager, service) = try await Self.fixtureManager(directory, layout: layout, supervisor: supervisor)
        let instance = layout.instance(service.id)
        do {
            try await manager.start(service.id)
            let pid = try #require(await manager.snapshot().state(of: service.id).processID)
            let record = try #require(contents(instance.activeRunFile))
            FileManager.default.createFile(atPath: instance.file(named: "exit-master").path, contents: nil)
            #expect(
                await eventually {
                    if case .stuck = await manager.snapshot().state(of: service.id) { true } else { false }
                })
            #expect(await manager.snapshot().state(of: service.id).processID == pid)
            #expect(contents(instance.activeRunFile) == record)
            #expect(!isLockFree(instance.lockFile))
            await #expect(throws: (any Error).self) { try await manager.stopAll() }
            await #expect(throws: (any Error).self) { try await manager.start(service.id) }
            await #expect(throws: (any Error).self) { try await manager.remove(service.id) }
            #expect(contents(instance.activeRunFile) == record)
            FileManager.default.createFile(atPath: instance.file(named: "finish-child").path, contents: nil)
            try await Task.sleep(for: .milliseconds(100))
            try await manager.stop(service.id)
            #expect(await manager.snapshot().state(of: service.id) == .stopped)
            #expect(!exists(instance.activeRunFile))
            #expect(isLockFree(instance.lockFile))
        } catch {
            FileManager.default.createFile(atPath: instance.file(named: "finish-child").path, contents: nil)
            _ = await supervisor.stopAll(policy: .forceful())
            throw error
        }
    }

    /// A paused server (`kill -STOP`, a debugger) is not an exit. When it ignores the stop signal
    /// after Jerd continues it, Quit is cancelled and the process, its record, and its lock stay.
    @Test func aPausedServiceThatCannotStopCancelsQuit() async throws {
        let directory = try TemporaryDirectory(" paused service")
        defer { directory.remove() }
        let supervisor = ProcessSupervisor()
        let layout = DataLayout(root: directory.path("Jerd")).databases
        let (manager, service) = try await Self.fixtureManager(
            directory, layout: layout, supervisor: supervisor, fixture: "graceful-process")
        let instance = layout.instance(service.id)
        try await manager.start(service.id)
        let pid = try #require(await manager.snapshot().state(of: service.id).processID)
        defer { kill(pid, SIGINT) }
        let record = try #require(contents(instance.activeRunFile))
        // The fixture ignores SIGTERM once it printed "ready".
        #expect(await eventually { text(instance.logFile).contains("ready") })
        #expect(await ProcessPause.pause(pid))
        try await Task.sleep(for: .milliseconds(50))
        #expect(await manager.snapshot().state(of: service.id) == .running(pid: pid))
        await #expect(throws: (any Error).self) { try await manager.stopAll() }
        guard case .stuck(pid, _) = await manager.snapshot().state(of: service.id) else {
            Issue.record("Expected a stuck service, got \(await manager.snapshot().state(of: service.id))")
            return
        }
        #expect(kill(pid, 0) == 0)
        #expect(contents(instance.activeRunFile) == record)
        #expect(!isLockFree(instance.lockFile))
        kill(pid, SIGINT)
        try await manager.stop(service.id)
        #expect(await manager.snapshot().state(of: service.id) == .stopped)
        #expect(!exists(instance.activeRunFile))
        #expect(isLockFree(instance.lockFile))
    }
}

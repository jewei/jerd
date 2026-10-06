import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdDatabases

@Suite struct DatabaseManagerTests {
    @Test func everyOperationNeedsLoadedSettings() async throws {
        let harness = try DatabaseHarness()
        let manager = harness.manager()
        await #expect(throws: DatabaseMessages.notLoaded) { try await manager.registerRuntimes(harness.runtimes) }
        await #expect(throws: DatabaseMessages.notLoaded) {
            _ = try await manager.add(name: "A", runtimeID: "x", port: 2_000)
        }
        await #expect(throws: DatabaseMessages.notLoaded) { try await manager.start(UUID()) }
        _ = try await manager.load()
        #expect(mode(harness.layout.root) == 0o700)
        #expect(!exists(harness.layout.servicesFile))
    }

    @Test func quitSucceedsWhenCorruptSettingsBlockTheLoad() async throws {
        let harness = try DatabaseHarness()
        try OwnedDirectory.create(harness.layout.root)
        try write("{not json", to: harness.layout.servicesFile)
        let manager = harness.manager()
        await #expect(throws: (any Error).self) { _ = try await manager.load() }
        try await manager.stopAll()
        // The load error is still reported, and the corrupt file is kept.
        await #expect(throws: (any Error).self) { _ = try await manager.load() }
        #expect(text(harness.layout.servicesFile) == "{not json")
        await #expect(throws: DatabaseMessages.notLoaded) { try await manager.start(UUID()) }
    }

    @Test func servicesStartAndStopIndependently() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let redis = try await manager.add(name: " Cache ", runtimeID: harness.runtime(.redis).id, port: 26_379)
        let postgres = try await manager.add(name: "Main", runtimeID: harness.runtime(.postgresql).id, port: 25_432)
        #expect(redis.name == "Cache")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await manager.start(redis.id) }
            group.addTask { try await manager.start(postgres.id) }
            try await group.waitForAll()
        }
        var snapshot = await manager.snapshot()
        #expect(snapshot.state(of: redis.id).processID != nil)
        #expect(snapshot.state(of: postgres.id).processID != nil)
        try await manager.stop(postgres.id)
        snapshot = await manager.snapshot()
        #expect(snapshot.state(of: postgres.id) == .stopped)
        #expect(snapshot.state(of: redis.id).processID != nil)
        #expect(await harness.processes.stopPolicies.last?.signal == SIGINT)
        try await manager.stopAll()
        #expect(await harness.processes.runningPIDs.isEmpty)
    }

    @Test func anOccupiedPortRegistersNothingAndStartsNothing() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        harness.lsof.occupy(26_380)
        await #expect(throws: JerdError.unavailable("Local port 26380 is occupied. No process was stopped.")) {
            _ = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_380)
        }
        #expect(await manager.snapshot().configuration.services.isEmpty)
        let service = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_381)
        harness.lsof.occupy(26_381)
        await #expect(throws: JerdError.unavailable("Local port 26381 is occupied. No process was stopped.")) {
            try await manager.start(service.id)
        }
        #expect(await manager.snapshot().state(of: service.id).failure?.contains("occupied") == true)
        #expect(!exists(harness.layout.instance(service.id).root))
        #expect(await harness.processes.requests.isEmpty)
    }

    @Test func aSecondServiceOnTheSamePortIsAPortConflict() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        _ = try await manager.add(name: "First", runtimeID: harness.runtime(.redis).id, port: 26_390)
        await #expect(throws: DatabaseMessages.portConflict(26_390, with: "First")) {
            _ = try await manager.add(name: "Second", runtimeID: harness.runtime(.mysql).id, port: 26_390)
        }
        #expect(harness.commands.requests(named: "lsof").count == 1)
    }

    @Test func editRenamesAndMovesOnlyAStoppedService() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        var service = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_400)
        try await manager.start(service.id)
        service.name = "  Renamed  "
        await #expect(throws: DatabaseMessages.stopBeforeEditing) { try await manager.edit(service) }
        try await manager.stop(service.id)
        service.port = 26_401
        try await manager.edit(service)
        let saved = try #require(await manager.snapshot().configuration.service(service.id))
        #expect(saved.name == "Renamed" && saved.port == 26_401)
        try await manager.start(service.id)
        #expect(text(harness.files(service.id).redisConfiguration).contains("port 26401\n"))
        try await manager.stop(service.id)
        let moved = DatabaseService(
            id: service.id, name: "Renamed", runtimeID: harness.runtime(.mysql).id, port: 26_401)
        await #expect(throws: DatabaseMessages.stopBeforeEditing) { try await manager.edit(moved) }
    }

    @Test func connectionSettingsNeedAFirstStart() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Main", runtimeID: harness.runtime(.mysql).id, port: 23_306)
        await #expect(throws: DatabaseMessages.startOnce) { _ = try await manager.connection(for: service.id) }
        try await manager.start(service.id)
        let password = try DatabaseCredentials.read(from: harness.files(service.id).layout.credentialsFile).password
        let connection = try await manager.connection(for: service.id)
        #expect(connection == DatabaseConnection(engine: .mysql, port: 23_306, password: password))
        try await manager.stopAll()
    }

    @Test func suggestionsSkipRegisteredAndOccupiedPorts() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        _ = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 6_379)
        harness.lsof.occupy(6_380)
        #expect(try await manager.suggestedPort(for: .redis) == 6_381)
    }

    @Test func aKnownRuntimeIDMustDescribeTheSameRuntime() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let redis = harness.runtime(.redis)
        try await manager.registerRuntime(redis)
        let moved = DatabaseRuntime(id: redis.id, engine: .redis, version: redis.version, path: "/elsewhere")
        await #expect(throws: DatabaseMessages.runtimeChanged) { try await manager.registerRuntime(moved) }
    }
}

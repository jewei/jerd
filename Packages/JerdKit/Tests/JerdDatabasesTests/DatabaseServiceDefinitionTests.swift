import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing
import os

@testable import JerdDatabases

/// Records setup phases and initializers, and checks their files while they exist. It acts
/// like the instance: it removes the secret files, and a successful initializer creates `data/`.
private final class RecordingStartSteps: SetupPhaseRunning, InitializerRunning {
    private let plans = OSAllocatedUnfairLock<[LaunchPlan]>(initialState: [])
    private let initializerPlans = OSAllocatedUnfairLock<[InitializerPlan]>(initialState: [])
    private let filesExisted = OSAllocatedUnfairLock(initialState: false)
    private let result: CommandResult

    init(initializerResult: CommandResult = CommandResult(status: 0, output: "")) { result = initializerResult }

    var recorded: [LaunchPlan] { plans.withLock { $0 } }
    var initializers: [InitializerPlan] { initializerPlans.withLock { $0 } }
    var hadFiles: Bool { filesExisted.withLock { $0 } }

    func runSetupPhase(_ plan: LaunchPlan) async throws {
        plans.withLock { $0.append(plan) }
        let files = plan.temporaryItems + plan.secretFiles
        filesExisted.withLock { $0 = files.allSatisfy { FileProbe.presence(at: $0) == .present } }
        plan.removeTemporaryItems()
        try plan.removeSecretFiles()
    }

    func runInitializer(_ plan: InitializerPlan) async throws -> CommandResult {
        initializerPlans.withLock { $0.append(plan) }
        filesExisted.withLock { $0 = plan.secretFiles.allSatisfy { FileProbe.presence(at: $0) == .present } }
        for file in plan.secretFiles { try AtomicFile.remove(file) }
        if result.succeeded, let data = DatabaseHarness.dataFolder(in: plan.request.arguments) {
            try FileManager.default.createDirectory(atPath: data, withIntermediateDirectories: false)
        }
        return result
    }
}

@Suite struct DatabaseServiceDefinitionTests {
    private func definition(
        _ harness: DatabaseHarness, _ engine: DatabaseEngine, id: UUID = UUID()
    )
        -> DatabaseServiceDefinition
    {
        let runtime = harness.runtime(engine)
        return DatabaseServiceDefinition(
            service: DatabaseService(id: id, name: "Local", runtimeID: runtime.id, port: 23_000), runtime: runtime,
            layout: harness.layout, temporaryRoot: FileManager.default.temporaryDirectory)
    }

    private func prepare(
        _ definition: DatabaseServiceDefinition, _ harness: DatabaseHarness, steps: RecordingStartSteps = .init()
    )
        async throws -> LaunchPlan
    {
        try OwnedDirectory.create(definition.profile.folder)
        let tools = StartTools(commands: harness.commands, setup: steps, initializer: steps)
        let plan = try await definition.prepareStart(tools)
        plan.removeTemporaryItems()
        return plan
    }

    @Test func aFirstRedisStartCreatesIdentityCredentialsDataAndMarker() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .redis)
        let steps = RecordingStartSteps()
        let plan = try await prepare(definition, harness, steps: steps)
        let layout = definition.engine.files.layout
        #expect(try MarkerFile.read(DatabaseIdentity.self, from: layout.runtimeIdentityFile) == definition.identity)
        #expect(try MarkerFile.read(DatabaseIdentity.self, from: layout.initializedMarkerFile) == definition.identity)
        let credentials = try DatabaseCredentials.read(from: layout.credentialsFile)
        #expect(mode(layout.credentialsFile) == 0o600)
        #expect(mode(layout.dataDirectory) == 0o700)
        #expect(plan.ports == [23_000])
        #expect(plan.secrets == [credentials.password])
        #expect(plan.temporaryItems.count == 1)
        #expect(plan.temporaryItems[0].lastPathComponent.hasPrefix("jerd-db-"))
        #expect(text(definition.engine.files.redisConfiguration).contains("requirepass \(credentials.password)\n"))
        #expect(steps.initializers.isEmpty)
        #expect(definition.profile.stopSignal == SIGTERM)
        #expect(definition.versionProbe.rule == .standalone(version: "8.4.11"))
    }

    @Test func aPostgresInitializerGetsAPasswordFileThatIsRemovedAfterwards() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .postgresql)
        let steps = RecordingStartSteps()
        _ = try await prepare(definition, harness, steps: steps)
        let initializer = try #require(steps.initializers.first)
        #expect(initializer.request.executable.lastPathComponent == "initdb")
        #expect(initializer.secretFiles == [definition.engine.files.initPassword])
        #expect(initializer.timeout == .seconds(120))
        #expect(
            initializer.secrets == [
                try DatabaseCredentials.read(from: definition.files.layout.credentialsFile).password
            ])
        #expect(steps.hadFiles)
        #expect(definition.profile.stopSignal == SIGINT)
        _ = try await prepare(definition, harness, steps: steps)
        #expect(steps.initializers.count == 1)
    }

    @Test func aMySQLFirstStartRunsASocketOnlySetupPhaseWithItsFiles() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .mysql)
        let setup = RecordingStartSteps()
        _ = try await prepare(definition, harness, steps: setup)
        let phase = try #require(setup.recorded.first)
        #expect(phase.ports.isEmpty)
        #expect(phase.request.arguments.contains("--skip-networking"))
        #expect(setup.hadFiles)
        #expect(Set(phase.secretFiles.map(\.lastPathComponent)) == ["bootstrap.sql", "bootstrap.cnf"])
        #expect(phase.temporaryItems.map { $0.lastPathComponent.hasPrefix("jerd-db-") } == [true])
        #expect(!exists(definition.engine.files.bootstrapSQL))
        #expect(exists(definition.engine.files.layout.initializedMarkerFile))
    }

    @Test func aFailedInitializerLeavesNoMarker() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .postgresql)
        let steps = RecordingStartSteps(initializerResult: CommandResult(status: 1, output: "FATAL: no space"))
        await #expect(throws: JerdError.processFailed("Database initialization failed: FATAL: no space")) {
            _ = try await prepare(definition, harness, steps: steps)
        }
        #expect(!exists(definition.engine.files.layout.initializedMarkerFile))
        #expect(!exists(definition.engine.files.initPassword))
    }

    @Test func aDefinitionNeverRunsAnInitializerOutsideTheInstance() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .mysql)
        try OwnedDirectory.create(definition.profile.folder)
        let tools = StartTools(commands: harness.commands, setup: RecordingStartSteps())
        await #expect(throws: JerdError.unavailable(ServiceMessages.initializerUnavailable)) {
            _ = try await definition.prepareStart(tools)
        }
        #expect(await harness.processes.requests.isEmpty)
        #expect(!exists(definition.engine.files.data))
    }

    @Test func dataWithoutAnIdentityIsUntrackedAndPreserved() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .redis)
        try write("keep", to: definition.engine.files.data.appendingPathComponent("dump.rdb"))
        await #expect(throws: DatabaseMessages.untracked) { _ = try await prepare(definition, harness) }
        #expect(text(definition.engine.files.data.appendingPathComponent("dump.rdb")) == "keep")
    }

    @Test func dataOfAnotherVersionIsPreserved() async throws {
        let harness = try DatabaseHarness()
        let id = UUID()
        _ = try await prepare(definition(harness, .redis, id: id), harness)
        let other = DatabaseRuntime(
            id: "redis-test", engine: .redis, version: "9.0.0", path: harness.runtime(.redis).path)
        let changed = DatabaseServiceDefinition(
            service: DatabaseService(id: id, name: "Local", runtimeID: other.id, port: 23_000), runtime: other,
            layout: harness.layout, temporaryRoot: FileManager.default.temporaryDirectory)
        await #expect(throws: DatabaseMessages.identityMismatch) { _ = try await prepare(changed, harness) }
    }

    @Test func missingCredentialsBesideDataAreRefused() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .redis)
        _ = try await prepare(definition, harness)
        try FileManager.default.removeItem(at: definition.engine.files.layout.credentialsFile)
        await #expect(throws: DatabaseMessages.credentialsMissing) { _ = try await prepare(definition, harness) }
    }

    @Test func partialDataIsNeverInitializedAgainAndAMarkerNeedsItsData() async throws {
        let harness = try DatabaseHarness()
        let definition = definition(harness, .postgresql)
        let steps = RecordingStartSteps()
        _ = try await prepare(definition, harness, steps: steps)
        try FileManager.default.removeItem(at: definition.engine.files.layout.initializedMarkerFile)
        await #expect(throws: DatabaseMessages.interrupted) {
            _ = try await prepare(definition, harness, steps: steps)
        }
        try MarkerFile.write(definition.identity, to: definition.engine.files.layout.initializedMarkerFile)
        try FileManager.default.removeItem(at: definition.engine.files.data)
        await #expect(throws: DatabaseMessages.initializedMismatch) {
            _ = try await prepare(definition, harness, steps: steps)
        }
        #expect(steps.initializers.count == 1)
    }

    @Test func aSocketFolderMustFitTheSocketPathLimit() throws {
        let long = URL(fileURLWithPath: "/" + String(repeating: "d", count: 80), isDirectory: true)
        #expect(throws: DatabaseMessages.socketFolder) { _ = try DatabaseSocketFolder.create(in: long) }
        let folder = try DatabaseSocketFolder.create(in: FileManager.default.temporaryDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(mode(folder) == 0o700)
        #expect(folder.lastPathComponent.count == "jerd-db-".count + 10)
    }
}

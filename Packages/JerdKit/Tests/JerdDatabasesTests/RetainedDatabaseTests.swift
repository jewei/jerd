import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdDatabases

@Suite struct RetainedDatabaseTests {
    /// A started and removed Redis service with stored data.
    private func removedService(_ harness: DatabaseHarness, _ manager: DatabaseManager) async throws -> DatabaseService
    {
        let service = try await manager.add(name: "Retained cache", runtimeID: harness.runtime(.redis).id, port: 26_600)
        try await manager.start(service.id)
        try write("same stored data", to: harness.files(service.id).data.appendingPathComponent("dump.rdb"))
        try await manager.remove(service.id)
        return service
    }

    @Test func removeKeepsDataAndCredentialsAndWritesARegistration() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await removedService(harness, manager)
        let files = harness.files(service.id)
        #expect(text(files.data.appendingPathComponent("dump.rdb")) == "same stored data")
        #expect(exists(files.layout.credentialsFile))
        let record = try MarkerFile.read(RemovedRegistration.self, from: files.layout.removedRegistrationFile)
        #expect(record.service == service && record.runtime == harness.runtime(.redis))
        #expect(await manager.snapshot().configuration.services.isEmpty)
        #expect(exists(harness.layout.previousServicesFile))
        let retained = try await manager.retainedDatabases()
        #expect(retained.map(\.id) == [service.id])
        #expect(retained.first?.canRestore == true)
        #expect((retained.first?.bytes ?? 0) > 0)
    }

    @Test func removingANeverStartedServiceLeavesNothingToRestore() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Unused", runtimeID: harness.runtime(.mysql).id, port: 26_610)
        try await manager.remove(service.id)
        #expect(!exists(harness.layout.instance(service.id).removedRegistrationFile))
        #expect(try await manager.retainedDatabases().isEmpty)
        try OwnedDirectory.create(harness.layout.instance(service.id).root)
        try write("old log", to: harness.layout.instance(service.id).logFile)
        #expect(try await manager.retainedDatabases().isEmpty)
    }

    @Test func aStaleRemovedRegistrationDoesNotBlockRemove() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await removedService(harness, manager)
        let restored = try await manager.restoreRegistration(service.id, name: "Back", port: 26_601)
        try write("corrupt", to: harness.files(service.id).layout.removedRegistrationFile)
        try await manager.remove(restored.id)
        let record = try MarkerFile.read(
            RemovedRegistration.self, from: harness.files(service.id).layout.removedRegistrationFile)
        #expect(record.service.name == "Back")
    }

    @Test(arguments: ["valid", "missing-marker", "wrong-version", "corrupt-registration", "legacy", "moved-runtime"])
    func retainedDataRequiresTheOriginalIdentity(scenario: String) async throws {
        let harness = try DatabaseHarness()
        let first = try await harness.loadedManager()
        let service = try await removedService(harness, first)
        let files = harness.files(service.id)
        let credentials = contents(files.layout.credentialsFile)
        try await damage(scenario, service: service, harness: harness, manager: first)
        let manager = harness.manager()
        _ = try await manager.load()
        let retained = try #require(try await manager.retainedDatabases().first)
        let valid = scenario == "valid" || scenario == "legacy"
        #expect(retained.id == service.id && retained.canRestore == valid)
        if scenario == "legacy" { #expect(retained.name == "Recovered Redis \(service.id.uuidString.prefix(6))") }
        if valid {
            let restored = try await manager.restoreRegistration(service.id, name: " Restored ", port: 26_602)
            #expect(restored.id == service.id && restored.runtimeID == service.runtimeID && restored.name == "Restored")
            #expect(await manager.snapshot().state(of: service.id) == .stopped)
            await #expect(throws: DatabaseMessages.alreadyRegisteredOrBusy) {
                _ = try await manager.restoreRegistration(service.id, name: "Again", port: 26_603)
            }
        } else {
            await #expect(throws: (any Error).self) {
                _ = try await manager.restoreRegistration(service.id, name: "Bad", port: 26_602)
            }
            #expect(await manager.snapshot().configuration.services.isEmpty)
        }
        #expect(text(files.data.appendingPathComponent("dump.rdb")) == "same stored data")
        #expect(contents(files.layout.credentialsFile) == credentials)
        if scenario == "corrupt-registration" { #expect(text(files.layout.removedRegistrationFile) == "corrupt") }
    }

    /// Changes the retained folder or the registry for one restore scenario.
    private func damage(
        _ scenario: String, service: DatabaseService, harness: DatabaseHarness, manager: DatabaseManager
    ) async throws {
        let files = harness.files(service.id)
        switch scenario {
        case "missing-marker": try FileManager.default.removeItem(at: files.layout.initializedMarkerFile)
        case "wrong-version":
            let changed = DatabaseIdentity(
                serviceID: service.id, runtimeID: service.runtimeID, engine: .redis, version: "9.0.0")
            try MarkerFile.write(changed, to: files.layout.runtimeIdentityFile)
        case "corrupt-registration": try write("corrupt", to: files.layout.removedRegistrationFile)
        case "legacy": try FileManager.default.removeItem(at: files.layout.removedRegistrationFile)
        default: break
        }
        if scenario == "moved-runtime" {
            // The same runtime ID in another folder is another runtime.
            var saved = try await manager.load()
            saved.runtimes = saved.runtimes.map { runtime in
                runtime.engine == .redis
                    ? DatabaseRuntime(id: runtime.id, engine: .redis, version: runtime.version, path: "/moved")
                    : runtime
            }
            try AtomicFile.write(
                JSONFileFormat.settings.makeEncoder().encode(saved), to: harness.layout.servicesFile)
        }
    }

    @Test func aRestoreCannotTakeAPortOfAnotherService() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await removedService(harness, manager)
        _ = try await manager.add(name: "Other", runtimeID: harness.runtime(.mysql).id, port: 26_620)
        await #expect(throws: DatabaseMessages.portConflict(26_620, with: "Other")) {
            _ = try await manager.restoreRegistration(service.id, name: "Back", port: 26_620)
        }
    }
}

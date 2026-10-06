import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

@Suite struct StorageUpdateTests {
    private func backups(_ harness: StorageHarness) throws -> [String] {
        guard exists(harness.storage.runtimeBackupsDirectory) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: harness.storage.runtimeBackupsDirectory.path)
    }

    @Test func runningStorageMovesToTheNewRuntimeWithABackupOfItsData() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.addBucket(name: "app-uploads", publicRead: false)
        try write("object", to: harness.storage.dataDirectory.appendingPathComponent("app-uploads/file"))
        let credentials = try #require(contents(harness.storage.credentialsFile))
        let updated = harness.updatedRuntime()
        try await manager.updateRuntime(updated)
        let snapshot = await manager.snapshot()
        #expect(snapshot.settings.runtime == updated && snapshot.processID != nil)
        #expect(snapshot.availableBuckets == ["app-uploads"])
        #expect(try MarkerFile.read(StorageRuntime.self, from: harness.storage.runtimeIdentityFile) == updated)
        let marker = try MarkerFile.read(StorageInitializedMarker.self, from: harness.storage.initializedMarkerFile)
        #expect(marker.runtime == updated && marker.credentialsHash == FileDigest.hexSHA256(of: credentials))
        #expect(contents(harness.storage.credentialsFile) == credentials)
        let backup = harness.storage.runtimeBackupsDirectory.appendingPathComponent(
            try #require(backups(harness).first))
        #expect(text(backup.appendingPathComponent("data/app-uploads/file")) == "object")
        #expect(contents(backup.appendingPathComponent("credentials.json")) == credentials)
        #expect(!exists(harness.storage.runtimeUpdateJournal))
        try await manager.stop()
    }

    @Test func storageThatNeverStartedGetsNoDataBeforeTheBackup() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.updateRuntime(harness.updatedRuntime())
        #expect(await manager.snapshot().state == .stopped)
        let backup = harness.storage.runtimeBackupsDirectory.appendingPathComponent(
            try #require(backups(harness).first))
        let saved = try FileManager.default.contentsOfDirectory(atPath: backup.path)
        #expect(Set(saved).isSubset(of: ["settings.json", "settings.previous.json"]))
        #expect(isLockFree(harness.storage.lockFile))
    }

    @Test func aMissingBucketAfterTheUpdateRestoresThePreviousRuntime() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.addBucket(name: "app-uploads", publicRead: false)
        harness.server.update { $0.buckets = [] }
        await #expect {
            try await manager.updateRuntime(harness.updatedRuntime())
        } throws: { error in
            (error as? JerdError)?.message
                == "Storage update failed. The previous runtime and data were restored. "
                + "The updated storage service did not return all registered buckets."
        }
        let snapshot = await manager.snapshot()
        #expect(snapshot.settings.runtime == harness.runtime && snapshot.processID != nil)
        #expect(try MarkerFile.read(StorageRuntime.self, from: harness.storage.runtimeIdentityFile) == harness.runtime)
        #expect(!exists(harness.storage.runtimeUpdateJournal))
        try await manager.stop()
    }

    @Test func aVersionMismatchOfTheNewRuntimeRestoresTheData() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        try await manager.stop()
        await #expect(throws: (any Error).self) {
            try await manager.updateRuntime(harness.updatedRuntime(version: "9.9.9"))
        }
        #expect(await manager.snapshot().state == .stopped)
        #expect(try StorageSettingsStore(layout: harness.storage).load().runtime == harness.runtime)
        try await manager.start()
        try await manager.stop()
    }

    @Test func changedDataIsNeverBackedUpOrUpdated() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        try await manager.stop()
        try write("{\"version\":\"changed\"}", to: harness.storage.formatFile)
        await #expect(throws: (any Error).self) { try await manager.updateRuntime(harness.updatedRuntime()) }
        #expect(try backups(harness).isEmpty)
        #expect(await manager.snapshot().settings.runtime == harness.runtime)
    }

    @Test func aPendingUpdateAllowsOnlyLoadStartAndStop() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        let saved = try #require(contents(harness.storage.settingsFile))
        let id = UUID()
        let folder = harness.storage.runtimeBackupsDirectory.appendingPathComponent(id.uuidString)
        try OwnedDirectory.create(folder)
        try AtomicFile.write(saved, to: folder.appendingPathComponent("settings.json"))
        let journal = RuntimeUpdateJournal(id: id, names: StorageManager.updateItems, present: ["settings.json"])
        try MarkerFile.write(journal, to: harness.storage.runtimeUpdateJournal)
        await #expect(throws: StorageMessages.updatePending) {
            try await manager.addBucket(name: "app", publicRead: false)
        }
        await #expect(throws: StorageMessages.updatePending) { try await manager.refreshBuckets() }
        await #expect(throws: StorageMessages.updatePending) {
            try await manager.edit(ports: StoragePorts(api: 19_000, console: 19_001))
        }
        try await manager.start()
        #expect(!exists(harness.storage.runtimeUpdateJournal))
        try await manager.stop()
    }
}

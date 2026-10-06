import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@Suite struct RuntimeUpdateBackupTests {
    static let messages = RuntimeUpdateTransaction.Messages(
        service: "Fake", restored: "The previous runtime was restored.",
        stopBeforeRecovery: "Stop the fake service before recovering its update.")

    static func transaction(_ harness: InstanceHarness, names: [String]) -> RuntimeUpdateTransaction {
        RuntimeUpdateTransaction(
            root: harness.folder, journalFile: harness.folder.appendingPathComponent("runtime-update.json"),
            backupsDirectory: harness.folder.appendingPathComponent("runtime-backups", isDirectory: true),
            lockFile: harness.lockFile, names: names, messages: messages)
    }

    @Test func anInterruptedUpdateRestoresDataAndKeepsTheFailedFiles() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        defer { Task { await instance.endMaintenance(lease) } }
        try write("original", to: harness.folder.appendingPathComponent("data/object"))
        try write("old runtime", to: harness.folder.appendingPathComponent("settings.json"))
        let journal = try await Self.transaction(harness, names: ["settings.json", "data", "new-file"])
            .beginBackup(holding: lease)
        #expect(journal.present == ["settings.json", "data"])
        try write("changed", to: harness.folder.appendingPathComponent("data/object"))
        try write("new runtime", to: harness.folder.appendingPathComponent("settings.json"))
        try write("created", to: harness.folder.appendingPathComponent("new-file"))
        // A new value, as after an app restart.
        let reloaded = Self.transaction(harness, names: ["settings.json", "data", "new-file"])
        #expect(reloaded.isPending)
        try await reloaded.restore(holding: lease)
        #expect(text(harness.folder.appendingPathComponent("data/object")) == "original")
        #expect(text(harness.folder.appendingPathComponent("settings.json")) == "old runtime")
        #expect(!exists(harness.folder.appendingPathComponent("new-file")))
        #expect(!reloaded.isPending)
        let backup = harness.folder.appendingPathComponent("runtime-backups/\(journal.id.uuidString)")
        let entries = try FileManager.default.contentsOfDirectory(atPath: backup.path)
        let failed = try #require(entries.first { $0.hasPrefix("failed-attempt-") })
        #expect(text(backup.appendingPathComponent("\(failed)/new-file")) == "created")
        #expect(text(backup.appendingPathComponent("data/object")) == "original")
        try await reloaded.restore(holding: lease)
    }

    @Test func aJournalWithAnOlderNameListIsStillRecovered() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        defer { Task { await instance.endMaintenance(lease) } }
        try write("old", to: harness.folder.appendingPathComponent("settings.json"))
        try write("current data", to: harness.folder.appendingPathComponent("access-key"))
        _ = try await Self.transaction(harness, names: ["settings.json"]).beginBackup(holding: lease)
        try write("new", to: harness.folder.appendingPathComponent("settings.json"))
        let newerBuild = Self.transaction(harness, names: ["access-key", "settings.json", "data"])
        try await newerBuild.restore(holding: lease)
        #expect(text(harness.folder.appendingPathComponent("settings.json")) == "old")
        #expect(text(harness.folder.appendingPathComponent("access-key")) == "current data")
    }

    @Test func aLinkAtACoveredNameStopsTheBackupWithoutAJournal() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        defer { Task { await instance.endMaintenance(lease) } }
        try FileManager.default.createSymbolicLink(
            at: harness.folder.appendingPathComponent("data"), withDestinationURL: harness.directory.path("missing"))
        let transaction = Self.transaction(harness, names: ["data"])
        await #expect(
            throws: JerdError.invalid("A service data file is not a regular file or directory. The update was stopped.")
        ) { _ = try await transaction.beginBackup(holding: lease) }
        #expect(!transaction.isPending)
    }

    @Test func everyJournalStepRequiresTheLease() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        await instance.endMaintenance(lease)
        let transaction = Self.transaction(harness, names: ["data"])
        await #expect(throws: JerdError.unavailable(ServiceMessages.staleLease)) {
            _ = try await transaction.beginBackup(holding: lease)
        }
        #expect(throws: JerdError.unavailable(ServiceMessages.staleLease)) { try transaction.commit(holding: lease) }
        await #expect(throws: JerdError.unavailable(ServiceMessages.staleLease)) {
            try await transaction.restore(holding: lease)
        }
    }

    @Test(arguments: ["{broken", #"{"id":"0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0","names":["a"],"present":["b"]}"#])
    func anInvalidJournalIsPreservedAndBlocksANewUpdate(_ bytes: String) async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        defer { Task { await instance.endMaintenance(lease) } }
        let journal = harness.folder.appendingPathComponent("runtime-update.json")
        try write(bytes, to: journal)
        let transaction = Self.transaction(harness, names: ["a"])
        await #expect(throws: JerdError.corrupt("The runtime update record is invalid. Backup files were preserved.")) {
            try await transaction.restore(holding: lease)
        }
        await #expect(
            throws: JerdError.unavailable("Recover the previous runtime update before starting another update.")
        ) {
            _ = try await transaction.beginBackup(holding: lease)
        }
        #expect(text(journal) == bytes)
    }
}

import Foundation
import JerdFoundation
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

@testable import JerdServiceKit

/// A journal must never name a backup that a power loss can make incomplete, and must never be
/// removed before its restored items are on the drive.
@Suite struct RuntimeUpdateDurabilityTests {
    @Test func theBackupIsFlushedBeforeTheJournalIsWritten() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        defer { Task { await instance.endMaintenance(lease) } }
        try write("original", to: harness.folder.appendingPathComponent("data/object"))
        var transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["data", "absent"])
        let journal = transaction.journalFile
        let events = harness.events
        transaction.flushData = { trees, folders in
            events.add("flush \(trees.map(\.lastPathComponent)) \(folders.map(\.lastPathComponent)) \(exists(journal))")
        }
        let written = try await transaction.beginBackup(holding: lease)
        #expect(events.events == ["flush [\"data\"] [\"\(written.id.uuidString)\", \"runtime-backups\"] false"])
        #expect(transaction.isPending)
    }

    @Test func theRestoreIsFlushedBeforeTheJournalIsRemoved() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        defer { Task { await instance.endMaintenance(lease) } }
        try write("original", to: harness.folder.appendingPathComponent("settings.json"))
        var transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        _ = try await transaction.beginBackup(holding: lease)
        try write("changed", to: harness.folder.appendingPathComponent("settings.json"))
        let journal = transaction.journalFile
        let events = harness.events
        transaction.flushData = { trees, folders in
            let failed = folders.first?.lastPathComponent.hasPrefix("failed-attempt-") == true
            events.add("flush \(trees.map(\.lastPathComponent)) \(failed) \(exists(journal))")
        }
        try await transaction.restore(holding: lease)
        #expect(events.events == ["flush [\"settings.json\"] true true"])
        #expect(!transaction.isPending)
        #expect(text(harness.folder.appendingPathComponent("settings.json")) == "original")
    }

    @Test func aFlushReachesEveryFileAndFolderOfATree() async throws {
        let directory = try TemporaryDirectory(" flush ü")
        defer { directory.remove() }
        try write("one", to: directory.path("tree/a"))
        try write("two", to: directory.path("tree/nested/b"))
        try await ServiceDataCopier.flush([directory.path("tree")], folders: [directory.url])
        await #expect(throws: (any Error).self) {
            try await ServiceDataCopier.flush([directory.path("missing")], folders: [])
        }
        try FileManager.default.createSymbolicLink(
            at: directory.path("tree/link"), withDestinationURL: directory.path("tree/a"))
        await #expect(
            throws: JerdError.invalid("A service data file is not a regular file or directory. The update was stopped.")
        ) { try await ServiceDataCopier.flush([directory.path("tree")], folders: []) }
    }
}

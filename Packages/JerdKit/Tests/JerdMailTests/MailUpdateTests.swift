import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import Testing

@testable import JerdMail

@Suite struct MailUpdateTests {
    private func backups(_ harness: MailHarness) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: harness.mail.runtimeBackupsDirectory.path)
    }

    @Test func aRunningInboxMovesToTheNewRuntimeAndKeepsABackup() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        try write("captured", to: harness.mail.inboxDatabaseFile)
        let updated = harness.updatedRuntime()
        try await manager.updateRuntime(updated)
        let snapshot = await manager.snapshot()
        #expect(snapshot.settings.runtime == updated)
        #expect(snapshot.processID != nil)
        #expect(try MarkerFile.read(MailRuntime.self, from: harness.mail.runtimeIdentityFile) == updated)
        #expect(try MarkerFile.read(MailRuntime.self, from: harness.mail.initializedMarkerFile) == updated)
        #expect(text(harness.mail.inboxDatabaseFile) == "captured")
        #expect(!exists(harness.mail.runtimeUpdateJournal))
        let backup = harness.mail.runtimeBackupsDirectory.appendingPathComponent(try #require(backups(harness).first))
        #expect(text(backup.appendingPathComponent("inbox/messages.sqlite")) == "captured")
        #expect(exists(backup.appendingPathComponent("settings.json")))
        try await manager.updateRuntime(updated)
        #expect(try backups(harness).count == 1)
        try await manager.stop()
    }

    @Test func aStoppedInboxIsStoppedAgainAfterItsUpdate() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.updateRuntime(harness.updatedRuntime())
        #expect(await manager.snapshot().state == .stopped)
        #expect(await harness.processes.requests.count == 1)
        #expect(isLockFree(harness.mail.lockFile))
        #expect(try MailSettingsStore(layout: harness.mail).load().runtime == harness.updatedRuntime())
    }

    @Test func aFailedUpdateRestoresTheInboxAndRestartsThePreviousRuntime() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        try write("captured", to: harness.mail.inboxDatabaseFile)
        await #expect {
            try await manager.updateRuntime(harness.updatedRuntime(version: "9.9.9"))
        } throws: { error in
            (error as? JerdError)?.message
                == "Mail update failed. The previous runtime and inbox were restored. \(MailMessages.versionMismatch)"
        }
        let snapshot = await manager.snapshot()
        #expect(snapshot.settings.runtime == harness.runtime)
        #expect(snapshot.processID != nil)
        #expect(try MarkerFile.read(MailRuntime.self, from: harness.mail.runtimeIdentityFile) == harness.runtime)
        #expect(text(harness.mail.inboxDatabaseFile) == "captured")
        #expect(!exists(harness.mail.runtimeUpdateJournal))
        let backup = harness.mail.runtimeBackupsDirectory.appendingPathComponent(try #require(backups(harness).first))
        let names = try FileManager.default.contentsOfDirectory(atPath: backup.path)
        #expect(names.contains { $0.hasPrefix("failed-attempt-") })
        try await manager.stop()
    }

    @Test func anInboxOfAnotherRuntimeIsNeverBackedUpOrChanged() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        try await manager.stop()
        try MarkerFile.write(harness.updatedRuntime(version: "2.0.0"), to: harness.mail.runtimeIdentityFile)
        await #expect(throws: (any Error).self) { try await manager.updateRuntime(harness.updatedRuntime()) }
        let made = exists(harness.mail.runtimeBackupsDirectory) ? try backups(harness) : []
        #expect(made.isEmpty)
        #expect(await manager.snapshot().settings.runtime == harness.runtime)
    }

    @Test func aPendingUpdateAllowsOnlyLoadStartAndStopAndStartRecoversIt() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        let saved = try #require(contents(harness.mail.settingsFile))
        try writeJournal(harness, settings: saved)
        try MailSettingsStore(layout: harness.mail).save(
            MailSettings(runtime: harness.updatedRuntime()), replacing: harness.runtime)
        await #expect(throws: MailMessages.updatePending) { try await manager.edit(ports: MailEditTests.ports) }
        await #expect(throws: MailMessages.updatePending) { try await manager.sendTestEmail() }
        await #expect(throws: MailMessages.updatePending) { try await manager.updateRuntime(harness.updatedRuntime()) }
        try await manager.stop()
        try await manager.start()
        #expect(!exists(harness.mail.runtimeUpdateJournal))
        #expect(contents(harness.mail.settingsFile) == saved)
        #expect(await manager.snapshot().settings.runtime == harness.runtime)
        try await manager.stop()
    }

    @Test func loadRecoversAnInterruptedUpdate() async throws {
        let harness = try MailHarness()
        _ = try await harness.loadedManager()
        let saved = try #require(contents(harness.mail.settingsFile))
        try writeJournal(harness, settings: saved)
        try MailSettingsStore(layout: harness.mail).save(
            MailSettings(runtime: harness.updatedRuntime()), replacing: harness.runtime)
        let restarted = harness.manager()
        #expect(try await restarted.load().runtime == harness.runtime)
        #expect(!exists(harness.mail.runtimeUpdateJournal))
        #expect(isLockFree(harness.mail.lockFile))
    }

    /// Simulates a crash after the backup: a journal and a backup of `settings.json` only.
    private func writeJournal(_ harness: MailHarness, settings: Data) throws {
        let id = UUID()
        let folder = harness.mail.runtimeBackupsDirectory.appendingPathComponent(id.uuidString)
        try OwnedDirectory.create(folder)
        try AtomicFile.write(settings, to: folder.appendingPathComponent("settings.json"))
        let journal = RuntimeUpdateJournal(id: id, names: MailManager.updateItems, present: ["settings.json"])
        try MarkerFile.write(journal, to: harness.mail.runtimeUpdateJournal)
    }
}

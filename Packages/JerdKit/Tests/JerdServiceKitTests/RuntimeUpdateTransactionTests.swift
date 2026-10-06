import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@Suite struct RuntimeUpdateTransactionTests {
    private func settings(_ harness: InstanceHarness) -> URL { harness.folder.appendingPathComponent("settings.json") }

    private func steps(
        _ harness: InstanceHarness, reloadFails: Bool = false, onReload: @escaping @Sendable () -> Void = {}
    ) -> RuntimeUpdateSteps {
        let settings = settings(harness)
        return RuntimeUpdateSteps(
            validatePrevious: { harness.events.add("validate") },
            apply: { try write("new runtime", to: settings) },
            reloadAfterRestore: {
                harness.events.add("reload")
                onReload()
                if reloadFails { throw JerdError.corrupt("The restored settings are invalid.") }
                return harness.definition(name: text(settings))
            })
    }

    @Test func aSuccessfulUpdateRunsTheNewRuntimeAndKeepsTheBackup() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance(harness.definition(name: "old runtime"))
        try await instance.start()
        try write("old runtime", to: settings(harness))
        let transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        try await transaction.run(on: instance, to: harness.definition(name: "new runtime"), steps: steps(harness))
        #expect(await instance.definition.profile.name == "new runtime")
        #expect(await instance.state.processID != nil)
        #expect(!transaction.isPending)
        let backups = try FileManager.default.contentsOfDirectory(atPath: transaction.backupsDirectory.path)
        #expect(backups.count == 1)
        #expect(!isLockFree(harness.lockFile))
        try await instance.stop()
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aStoppedServiceIsStoppedAgainAfterItsUpdate() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        try await transaction.run(on: instance, to: harness.definition(name: "new runtime"), steps: steps(harness))
        #expect(await instance.state == .stopped)
        #expect(await harness.processes.requests.count == 1)
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aFailedStartRestoresTheDataAndRestartsTheOldRuntime() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance(harness.definition(name: "old runtime"))
        try await instance.start()
        try write("old runtime", to: settings(harness))
        harness.setVersionOutput("server 9.9.9")
        let transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        await #expect {
            // The old runtime passes its version check again after the restore.
            let steps = steps(harness, onReload: { harness.setVersionOutput("server 1.2.3") })
            try await transaction.run(on: instance, to: harness.definition(name: "new runtime"), steps: steps)
        } throws: { error in
            (error as? JerdError)?.message.hasPrefix("Fake update failed. The previous runtime was restored.") == true
        }
        #expect(await instance.state.processID != nil)
        #expect(text(settings(harness)) == "old runtime")
        #expect(await instance.definition.profile.name == "old runtime")
        #expect(!transaction.isPending)
    }

    @Test func aRestoredStoppedServiceIsStoppedAndTheErrorNamesTheCause() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance(harness.definition(name: "old runtime"))
        try write("old runtime", to: settings(harness))
        harness.setVersionOutput("server 9.9.9")
        let transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        await #expect(
            throws: JerdError.processFailed(
                "Fake update failed. The previous runtime was restored. The fake server version does not match.")
        ) {
            try await transaction.run(on: instance, to: harness.definition(name: "new runtime"), steps: steps(harness))
        }
        #expect(await instance.state == .stopped)
        #expect(text(settings(harness)) == "old runtime")
        #expect(!transaction.isPending)
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aFailedRecoveryKeepsTheBackupAndReportsBothErrors() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        harness.setVersionOutput("server 9.9.9")
        let transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        await #expect(
            throws: JerdError.processFailed(
                "Fake update failed. Backup files were preserved. The restored settings are invalid.")
        ) {
            try await transaction.run(
                on: instance, to: harness.definition(name: "new"), steps: steps(harness, reloadFails: true))
        }
        guard case .failed(let reason) = await instance.state else {
            Issue.record("Expected a failed instance")
            return
        }
        #expect(reason.hasPrefix("Fake update failed. The fake server version does not match. Recovery:"))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aPendingJournalRefusesTheUpdateBeforeTheServerStops() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        let pid = try #require(await instance.processID)
        let transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        try write("{}", to: transaction.journalFile)
        await #expect(
            throws: JerdError.unavailable("Recover the previous runtime update before starting another update.")
        ) {
            try await transaction.run(on: instance, to: harness.definition(name: "new"), steps: steps(harness))
        }
        #expect(await instance.state == .running(pid: pid))
        #expect(await harness.processes.stopPolicies.isEmpty)
        #expect(await harness.processes.requests.count == 1)
        #expect(harness.events.events == ["prepare", "complete"])
    }

    @Test func recoveryRefusesWhileAProcessRunsAndRestoresOtherwise() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let transaction = RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
        let lease = try await instance.beginMaintenance()
        try write("old runtime", to: settings(harness))
        _ = try await transaction.beginBackup(holding: lease)
        try write("half updated", to: settings(harness))
        await instance.endMaintenance(lease)
        try await instance.start()
        await #expect(throws: JerdError.unavailable("Stop the fake service before recovering its update.")) {
            try await transaction.recoverIfNeeded(on: instance, reload: { harness.definition() })
        }
        try await instance.stop()
        try await transaction.recoverIfNeeded(on: instance, reload: { harness.definition(name: "recovered") })
        #expect(text(settings(harness)) == "old runtime")
        #expect(await instance.definition.profile.name == "recovered")
        #expect(!transaction.isPending)
        try await transaction.recoverIfNeeded(on: instance, reload: { harness.definition() })
    }
}

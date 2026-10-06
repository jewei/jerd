import Foundation
import JerdProcess
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Advanced model")
@MainActor
struct AdvancedModelTests {
    private func makeModel(
        ports: InMemoryAdvancedPorts = InMemoryAdvancedPorts(
            findings: SampleData.findings, backups: SampleData.backups, registrations: SampleData.registrations,
            httpsStatus: SampleData.httpsRecovery),
        panels: InMemoryFilePanels = InMemoryFilePanels(), shell: InMemoryShell = InMemoryShell()
    ) async -> AdvancedModel {
        let model = AdvancedModel(
            recovery: ports, executables: ports, https: ports, panels: panels, workspace: shell)
        await model.load()
        return model
    }

    @Test("Load reads registrations and the HTTPS report, but no records before an inspection")
    func loadDoesNotInspect() async {
        let model = await makeModel()
        #expect(model.registrations == SampleData.registrations)
        #expect(model.httpsRecovery == SampleData.httpsRecovery)
        #expect(model.findings.isEmpty)
        #expect(!model.hasInspected)
    }

    @Test("Inspect reads records and backups")
    func inspect() async {
        let model = await makeModel()
        await model.inspect()?.value
        #expect(model.findings == SampleData.findings)
        #expect(model.backups == SampleData.backups)
        #expect(model.hasInspected)
        #expect(model.operation == .idle)
    }

    @Test("A destructive step runs only after confirmation")
    func confirmationRequired() async {
        let ports = InMemoryAdvancedPorts(backups: SampleData.backups)
        let model = await makeModel(ports: ports)
        model.confirmation = .deleteBackup(SampleData.backups[0])
        #expect(await ports.calls.isEmpty)
        model.confirmation = nil
        #expect(model.confirm() == nil)
        model.confirmation = .deleteBackup(SampleData.backups[0])
        await model.confirm()?.value
        #expect(await ports.calls == ["remove backup \(SampleData.backups[0].id)"])
        #expect(model.confirmation == nil)
        #expect(model.backups == [SampleData.backups[1]])
    }

    @Test(
        "Every step has the right confirmation copy; a stale record is cleared, not recovered",
        arguments: [
            (
                AdvancedConfirmation.forFinding(SampleData.findings[1]), "Clear this stale record?",
                "Clear Stale Record", false
            ),
            (.forFinding(SampleData.findings[0]), "Recover this saved service?", "Recover Service", false),
            (.deleteBackup(SampleData.backups[0]), "Delete this retained backup?", "Delete Backup", true),
            (
                .removePHP(SampleData.registrations.php[0]), "Remove this PHP runtime registration?",
                "Remove Registration", true
            ),
            (
                .restoreHTTPS(SampleData.httpsRecovery), "Restore the previous HTTPS setup?", "Restore Previous Setup",
                false
            ),
            (.removeHTTPS(SampleData.httpsRecovery), "Remove the tracked HTTPS setup?", "Remove Tracked Setup", true),
        ])
    func confirmationCopy(step: AdvancedConfirmation, title: String, confirm: String, destructive: Bool) {
        #expect(step.title == title)
        #expect(step.confirmTitle == confirm)
        #expect(step.isDestructive == destructive)
        #expect(!step.message.isEmpty)
    }

    @Test("HTTPS recovery runs the approved action and reads the report again")
    func httpsRecovery() async {
        let ports = InMemoryAdvancedPorts(httpsStatus: SampleData.httpsRecovery)
        let model = await makeModel(ports: ports)
        model.confirmation = .removeHTTPS(SampleData.httpsRecovery)
        await model.confirm()?.value
        #expect(await ports.calls == ["recover HTTPS removeSetup"])
        #expect(model.httpsRecovery == nil)
    }

    @Test("A failed step shows once as the page failure and keeps the data; dismiss clears it")
    func failure() async {
        let ports = InMemoryAdvancedPorts(findings: SampleData.findings)
        let model = await makeModel(ports: ports)
        await model.inspect()?.value
        await ports.configure { $0.failure = "The saved service did not stop within 30 seconds." }
        model.confirmation = .forFinding(SampleData.findings[0])
        await model.confirm()?.value
        #expect(model.operation == .failed(message: "The saved service did not stop within 30 seconds."))
        #expect(model.findings == SampleData.findings)
        model.dismissFailure()
        #expect(model.operation == .idle)
    }

    @Test("PHP import asks for the CLI, then the matching FPM; a cancel stops without a call")
    func choosePHP() async {
        let ports = InMemoryAdvancedPorts()
        let panels = InMemoryFilePanels(answers: [URL(fileURLWithPath: "/opt/php/bin/php"), nil])
        let model = await makeModel(ports: ports, panels: panels)
        await model.choosePHP()?.value
        #expect(
            panels.requests.map(\.message) == [
                "Select a trusted PHP CLI executable.", "Select the matching PHP-FPM executable.",
            ])
        #expect(await ports.calls.isEmpty)
        panels.answers = [URL(fileURLWithPath: "/opt/php/bin/php"), URL(fileURLWithPath: "/opt/php/sbin/php-fpm")]
        await model.choosePHP()?.value
        #expect(await ports.calls == ["import PHP /opt/php/bin/php /opt/php/sbin/php-fpm"])
    }

    @Test("Caddy import uses one panel")
    func chooseCaddy() async {
        let ports = InMemoryAdvancedPorts()
        let panels = InMemoryFilePanels(answers: [URL(fileURLWithPath: "/opt/caddy")])
        let model = await makeModel(ports: ports, panels: panels)
        await model.chooseCaddy()?.value
        #expect(panels.requests.map(\.prompt) == ["Select Executable"])
        #expect(await ports.calls == ["import Caddy /opt/caddy"])
    }

    @Test("Show in Finder reveals the backup folder")
    func reveal() async {
        let shell = InMemoryShell()
        let model = await makeModel(shell: shell)
        model.reveal(SampleData.backups[0])
        #expect(shell.revealedURLs == [SampleData.backups[0].directory])
    }
}

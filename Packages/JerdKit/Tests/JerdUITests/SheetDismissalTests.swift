import JerdDatabases
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

/// A sheet that AppKit ends without its buttons, for example when Quit ends every open sheet,
/// ends exactly as its Cancel ends it. No sheet asks before it ends, so Quit does not ask
/// either (see the JerdUI README, "Sheets and Quit").
// The full run renders snapshots on the main actor for minutes, so the limit is wide; it only
// stops a hang.
@Suite("Sheet dismissal", .timeLimit(.minutes(5)))
@MainActor
struct SheetDismissalTests {
    @Test("A dismissal by SwiftUI runs the sheet's own dismissal; a new item never does")
    func itemBinding() {
        var item: String? = "editor"
        var dismissals = 0
        let binding = SheetBinding.item({ item }, dismiss: { dismissals += 1 })
        #expect(binding.wrappedValue == "editor")
        binding.wrappedValue = "restore"
        #expect(dismissals == 0)
        #expect(item == "editor")
        binding.wrappedValue = nil
        #expect(dismissals == 1)
        item = nil
        #expect(binding.wrappedValue == nil)
    }

    @Test("A presented flag runs the sheet's own dismissal when SwiftUI clears it")
    func flagBinding() {
        var dismissals = 0
        let binding = SheetBinding.isPresented({ true }, dismiss: { dismissals += 1 })
        binding.wrappedValue = true
        #expect(dismissals == 0)
        binding.wrappedValue = false
        #expect(dismissals == 1)
    }

    @Test("An HTTPS approval sheet that AppKit ends discards the waiting change, as Cancel does")
    func approvalDismissalDiscards() async throws {
        let port = InMemorySitesPort(setup: HTTPSSetupStatus())
        let harness = await SitesHarness.launched(sites: port)
        await harness.model.startAll()?.value
        _ = try #require(harness.model.sheet?.approval)
        SheetBinding.item({ harness.model.sheet }, dismiss: harness.model.dismissSheet).wrappedValue = nil
        #expect(harness.model.sheet == nil)
        for _ in 0..<2_000 where await !port.calls.contains("discard") {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(await port.calls.contains("discard"))
    }

    @Test("A site editor that AppKit ends closes without a save")
    func siteEditorDismissal() async {
        let harness = await SitesHarness.launched()
        harness.model.beginAdd()
        #expect(harness.model.sheet?.editor != nil)
        harness.model.dismissSheet()
        #expect(harness.model.sheet == nil)
        #expect(harness.model.operation == .idle)
    }

    @Test("A tunnel editor that AppKit ends forgets the typed token")
    func tunnelEditorDismissalClearsToken() async throws {
        let harness = await SitesHarness.launched()
        let model = harness.model.tunnels
        model.beginEdit(SampleData.docsTunnel, sites: harness.model.sites)
        let editor = try #require(model.sheet?.editor)
        editor.token = "typed-but-not-saved"
        SheetBinding.item({ model.sheet }, dismiss: model.cancelEditor).wrappedValue = nil
        #expect(model.sheet == nil)
        #expect(editor.token.isEmpty)
    }

    @Test("A database sheet that AppKit ends drops its draft, as Cancel does")
    func databaseDismissalDropsDraft() async {
        let fixture = AppFixture(services: InMemoryServicePorts(.populated))
        await fixture.state.launch()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        #expect(model.editor != nil)
        model.dismissSheet()
        #expect(model.sheet == nil)
        #expect(model.editor == nil)
        model.beginRestore(SampleServices.retained[0])
        #expect(model.sheet == .restore)
        model.dismissSheet()
        #expect(model.sheet == nil)
        #expect(model.restoreDraft == nil)
    }
}

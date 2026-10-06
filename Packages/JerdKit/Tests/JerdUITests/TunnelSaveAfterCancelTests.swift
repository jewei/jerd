import Foundation
import JerdTunnels
import JerdUIFixtures
import Testing

@testable import JerdUI

/// Cancel stays enabled while a tunnel saves. A save that ends after Cancel follows the rules
/// of a site save: a failure shows once on the page, and a success does not move the page.
@Suite("Tunnel save after Cancel", .timeLimit(.minutes(1)))
@MainActor
struct TunnelSaveAfterCancelTests {
    @Test("A save that fails after Cancel shows its failure once, on the page")
    func lateFailureShowsOnPage() async throws {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        let (editor, gate) = try await startHeldEdit(harness, port: port)
        let save = harness.model.tunnels.save(editor)
        harness.model.tunnels.cancelEditor()
        await port.configure { $0.failure = "This Cloudflare tunnel is already saved in Jerd." }
        await gate.open()
        await save?.value
        #expect(harness.model.tunnels.operation == .failed(message: "This Cloudflare tunnel is already saved in Jerd."))
        #expect(editor.failure == nil)
        #expect(harness.recorder.shown.isEmpty)
    }

    @Test("A save that succeeds after Cancel does not navigate")
    func lateSuccessDoesNotNavigate() async throws {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        let (editor, gate) = try await startHeldEdit(harness, port: port)
        let save = harness.model.tunnels.save(editor)
        harness.model.tunnels.cancelEditor()
        await gate.open()
        await save?.value
        #expect(harness.model.tunnels.operation == .idle)
        #expect(harness.recorder.shown.isEmpty)
        #expect(await port.calls.contains("save docs.example.com token=true"))
    }

    @Test("A save that succeeds with the editor open closes it and shows the tunnel")
    func openEditorNavigates() async throws {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        let (editor, gate) = try await startHeldEdit(harness, port: port)
        let save = harness.model.tunnels.save(editor)
        await gate.open()
        await save?.value
        #expect(harness.model.tunnels.sheet == nil)
        #expect(harness.recorder.shown == [.item(.tunnel(SampleData.docsTunnelID))])
    }

    /// Opens the editor of the stopped sample tunnel, ready to save, with a held port.
    private func startHeldEdit(
        _ harness: SitesHarness, port: InMemoryTunnelsPort
    ) async throws -> (TunnelEditorModel, FixtureGate) {
        let gate = FixtureGate()
        await port.configure { $0.saveGate = gate }
        harness.model.tunnels.beginEdit(SampleData.docsTunnel, sites: harness.model.sites)
        let editor = try #require(harness.model.tunnels.sheet?.editor)
        editor.token = "rotated"
        editor.routeChecked = true
        return (editor, gate)
    }
}

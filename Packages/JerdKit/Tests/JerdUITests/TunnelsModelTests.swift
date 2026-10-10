import Foundation
import JerdTunnels
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Tunnels model", .timeLimit(.minutes(1)))
@MainActor
struct TunnelsModelTests {
    @Test("Launch loads the settings, then connects the startup tunnels and keeps each failure")
    func launchConnectsStartupTunnels() async {
        let port = InMemoryTunnelsPort()
        await port.configure { port in
            port.startupFailures = [
                TunnelStartupFailure(id: SampleData.docsTunnelID, name: "Docs staging", message: "Token missing.")
            ]
        }
        let harness = await SitesHarness.launched(tunnels: port)
        let model = harness.model.tunnels
        #expect(model.isLoaded)
        #expect(model.state(of: SampleData.previewTunnelID) == .connected)
        #expect(model.startupFailures == [SampleData.docsTunnelID: "Token missing."])
        #expect(model.connectedCount == 1)
    }

    @Test("A failed load keeps the file and says so")
    func loadFailure() async {
        let port = InMemoryTunnelsPort()
        await port.configure { $0.loadFailure = "Cannot read tunnel settings." }
        let harness = await SitesHarness.launched(tunnels: port)
        #expect(!harness.model.tunnels.isLoaded)
        #expect(
            harness.model.tunnels.loadFailure
                == "Tunnel settings could not be loaded. The existing file was preserved. Cannot read tunnel settings.")
        #expect(await !port.calls.contains("connect startup"))
    }

    @Test("Connect asks first; Remove asks first and stops a running connector")
    func confirmations() async {
        let harness = await SitesHarness.launched()
        let model = harness.model.tunnels
        model.confirmation = .connect(SampleData.docsTunnel)
        #expect(await !harness.tunnels.calls.contains { $0.hasPrefix("connect 9") })
        await model.confirm()?.value
        #expect(model.state(of: SampleData.docsTunnelID) == .connected)
        model.confirmation = .remove(SampleData.docsTunnel)
        await model.confirm()?.value
        #expect(model.registration(SampleData.docsTunnelID) == nil)
        let calls = await harness.tunnels.calls
        #expect(calls.suffix(2) == ["stop 90415263", "remove 90415263"])
    }

    @Test("Stop runs outside the edit lock and its failure shows on the page")
    func stopFailure() async {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        await port.configure { $0.stopFails = true }
        await harness.model.tunnels.stop(SampleData.previewTunnel)?.value
        #expect(
            harness.model.tunnels.stopFailures[SampleData.previewTunnelID] == "The tunnel has not stopped. Retry Stop.")
        #expect(harness.model.tunnels.stoppingIDs.isEmpty)
        #expect(harness.model.tunnels.isActive(SampleData.previewTunnelID))
    }

    @Test("Save never connects, clears the token, and shows the tunnel")
    func saveNeverConnects() async throws {
        let harness = await SitesHarness.launched(tunnels: InMemoryTunnelsPort(configuration: TunnelConfiguration()))
        let model = harness.model.tunnels
        model.beginAdd(sites: harness.model.sites)
        let editor = try #require(model.sheet?.editor)
        await waitUntil { !editor.metricsPort.isEmpty }
        #expect(editor.metricsPort == "20243")
        editor.name = "Studio preview"
        editor.hostname = "Preview.Example.com"
        editor.token = "secret-token"
        #expect(editor.routing == .local)
        #expect(!editor.routeChecked)
        #expect(editor.canSave)
        await model.save(editor)?.value
        #expect(model.sheet == nil)
        #expect(editor.token.isEmpty)
        let saved = try #require(model.registrations.first)
        #expect(saved.hostname == "preview.example.com")
        #expect(saved.routing == .local)
        #expect(saved.originURL == TunnelEditorModel.defaultOrigin)
        #expect(model.state(of: saved.id) == .stopped)
        #expect(harness.recorder.shown == [.item(.tunnel(saved.id))])
        let calls = await harness.tunnels.calls
        #expect(!calls.contains { $0.hasPrefix("connect ") && $0 != "connect startup" })
    }

    @Test("A failed save stays in the editor; Cancel forgets the typed token")
    func saveFailure() async throws {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        let model = harness.model.tunnels
        model.beginEdit(SampleData.docsTunnel, sites: harness.model.sites)
        let editor = try #require(model.sheet?.editor)
        editor.token = "rotated"
        editor.routeChecked = true
        await port.configure { $0.failure = "This Cloudflare tunnel is already saved in Jerd." }
        await model.save(editor)?.value
        #expect(editor.failure == "This Cloudflare tunnel is already saved in Jerd.")
        #expect(model.operation == .idle)
        model.cancelEditor()
        #expect(model.sheet == nil)
        #expect(editor.token.isEmpty)
    }

    @Test("Edit of a running tunnel does not open")
    func editNeedsStop() async {
        let harness = await SitesHarness.launched()
        harness.model.tunnels.beginEdit(SampleData.previewTunnel, sites: harness.model.sites)
        #expect(harness.model.tunnels.sheet == nil)
    }

    @Test("Choose Executable checks the file and uses it")
    func chooseRuntime() async {
        let panels = InMemoryFilePanels(answers: [URL(fileURLWithPath: "/opt/cloudflared/cloudflared")])
        let harness = await SitesHarness.launched(panels: panels)
        await harness.model.tunnels.chooseRuntime()?.value
        #expect(await harness.tunnels.calls.contains("use runtime /opt/cloudflared/cloudflared"))
        #expect(panels.requests.first?.prompt == "Use Executable")
    }

    @Test("The log sheet loads the redacted log")
    func log() async throws {
        let harness = await SitesHarness.launched()
        harness.model.tunnels.showLog(SampleData.previewTunnel)
        guard case .log(let log) = harness.model.tunnels.sheet else {
            Issue.record("No log sheet")
            return
        }
        await log.load()
        #expect(log.text == SampleData.tunnelLog)
        #expect(log.title == "Connector Log")
        #expect(log.subtitle.hasPrefix("Studio preview. "))
    }

    @Test("The log sheet ends with one Done button on the far right; Refresh is on the leading side")
    func logFooter() async throws {
        let harness = await SitesHarness.launched()
        let model = harness.model.tunnels
        model.showLog(SampleData.previewTunnel)
        guard case .log(let log) = model.sheet else {
            Issue.record("No log sheet")
            return
        }
        let confirmation = TunnelLogSheet.confirmation(model: model, log: log)
        #expect(confirmation.title == "Done")
        #expect(confirmation.cancelTitle == nil)
        #expect(confirmation.usesReturnKey)
        #expect(try #require(confirmation.secondary).title == "Refresh")
        confirmation.perform()
        #expect(model.sheet == nil)
    }

    @Test("Copy and Open use the public address")
    func links() async {
        let harness = await SitesHarness.launched()
        harness.model.tunnels.copyAddress(SampleData.previewTunnel)
        harness.model.tunnels.openInBrowser(SampleData.previewTunnel)
        #expect(harness.shell.pasteboard == ["https://preview.example.com"])
        #expect(harness.clipboard.feedback?.text == "Copied public address")
        #expect(harness.shell.openedURLs.map(\.absoluteString) == ["https://preview.example.com"])
    }

    @Test("Quit stops every connector; a connector that does not stop keeps Jerd open")
    func shutdown() async {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        await port.configure { $0.stopFails = true }
        #expect(await !harness.model.tunnels.shutdown())
        #expect(harness.model.tunnels.operation.failureMessage != nil)
        harness.model.tunnels.resumeAfterCancelledQuit()
        #expect(!harness.model.tunnels.isShuttingDown)
        await port.configure { $0.stopFails = false }
        #expect(await harness.model.tunnels.shutdown())
        #expect(harness.model.tunnels.connectedCount == 0)
    }
}

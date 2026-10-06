import Foundation
import JerdDesign
import JerdTunnels
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

@Suite("Sites policies")
@MainActor
struct SitesPolicyTests {
    private let studio = SampleData.studio

    @Test(
        "A site's status: disabled, served, waiting while others run, working, then the environment",
        arguments: [
            (SampleData.legacy, EnvironmentState.running, [SampleData.studioID], false, "Disabled", StatusTone.idle),
            (SampleData.studio, .running, [SampleData.studioID], false, "Ready", .ready),
            (SampleData.northwind, .running, [SampleData.studioID], false, "Not running", .idle),
            (SampleData.studio, .stopped, [], true, "Working…", .busy),
            (SampleData.studio, .stopped, [], false, "Stopped", .idle),
            (SampleData.studio, .setupRequired, [], false, "Setup required", .attention),
            (SampleData.studio, .failed("PHP-FPM failed."), [], false, "Failed", .failed),
        ])
    func siteStatus(
        site: Site, state: EnvironmentState, ids: [UUID], working: Bool, label: String, tone: StatusTone
    ) {
        let status = SiteStatusPolicy.site(
            site, environment: EnvironmentSnapshot(state: state, siteIDs: Set(ids)), isWorking: working)
        #expect(status == DisplayStatus(label, tone: tone))
    }

    @Test(
        "Tunnel states map to words and tones; failed is 'Needs attention'",
        arguments: [
            (TunnelState.connected, "Connected", StatusTone.ready),
            (.connecting, "Connecting…", .busy),
            (.reconnecting, "Reconnecting…", .busy),
            (.stopped, "Stopped", .idle),
            (.failed("Token rejected."), "Needs attention", .failed),
        ])
    func tunnelStatus(state: TunnelState, label: String, tone: StatusTone) {
        #expect(TunnelStatusPolicy.status(state) == DisplayStatus(label, tone: tone))
    }

    @Test("A missing or empty selection falls back to the first site, then the first tunnel")
    func selection() {
        let site = UUID()
        let tunnel = UUID()
        #expect(SitesSelectionPolicy.resolve(.tunnel(tunnel), siteIDs: [site], tunnelIDs: [tunnel]) == .tunnel(tunnel))
        #expect(SitesSelectionPolicy.resolve(.site(UUID()), siteIDs: [site], tunnelIDs: [tunnel]) == .site(site))
        #expect(SitesSelectionPolicy.resolve(nil, siteIDs: [], tunnelIDs: [tunnel]) == .tunnel(tunnel))
        #expect(SitesSelectionPolicy.resolve(.database(UUID()), siteIDs: [], tunnelIDs: []) == nil)
    }

    @Test("Confirmations: remove keeps project files and is destructive; reconnect is not")
    func confirmations() {
        let remove = SitesConfirmation.removeSite(studio)
        #expect(remove.title == "Remove this registration?")
        #expect(remove.message.contains("never deletes them"))
        #expect(remove.isDestructive)
        #expect(SitesConfirmation.removeSystemSetup.isDestructive)
        #expect(!SitesConfirmation.reconnectHelper.isDestructive)
        #expect(TunnelConfirmation.remove(SampleData.docsTunnel).isDestructive)
        #expect(!TunnelConfirmation.connect(SampleData.docsTunnel).isDestructive)
        #expect(TunnelConfirmation.connect(SampleData.docsTunnel).title == "Connect Docs staging?")
    }

    @Test("Connection checks claim a pass only with evidence")
    func checks() async {
        let harness = await SitesHarness.launched(sites: InMemorySitesPort(setup: HTTPSSetupStatus()))
        let checks = SiteCheck.checks(for: studio, in: harness.model)
        #expect(checks.allSatisfy { !$0.passed })
        #expect(
            checks.map(\.result) == [
                "Approval required", "Checked when the site starts", "Checked when the site starts",
            ])
    }

    @Test("Tunnel editor: a hostname with a scheme, an IP address, a low port, or a removed site blocks Save")
    func tunnelEditorRules() {
        let editor = TunnelEditorModel(tunnel: nil, sites: [studio], suggestedPort: 20_241)
        editor.name = "Preview"
        editor.token = "token"
        editor.routeChecked = true
        editor.hostname = "https://preview.example.com"
        #expect(editor.validationMessage != nil)
        #expect(!editor.canSave)
        editor.hostname = "203.0.113.10"
        #expect(!editor.canSave)
        editor.hostname = "preview.example.com"
        #expect(editor.canSave)
        editor.metricsPort = "80"
        #expect(editor.validationMessage == "Enter a metrics port from 1024 to 65535.")
        editor.metricsPort = "20241"
        editor.siteID = UUID()
        #expect(editor.isSiteMissing)
        #expect(!editor.canSave)
        editor.siteID = studio.id
        #expect(editor.canSave)
        #expect(editor.registration?.originURL == nil)
    }

    @Test("Tunnel editor: an edit keeps the saved token when the field is empty")
    func tunnelEditorKeepsToken() {
        let editor = TunnelEditorModel(tunnel: SampleData.docsTunnel, sites: [])
        editor.routeChecked = true
        #expect(editor.canSave)
        #expect(editor.tokenToSave == nil)
        #expect(editor.title == "Edit Cloudflare Tunnel")
    }
}

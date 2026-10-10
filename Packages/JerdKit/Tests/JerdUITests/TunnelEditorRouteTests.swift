import Foundation
import JerdTunnels
import JerdUIFixtures
import Testing

@testable import JerdUI

/// The route rules of the tunnel editor: who sets the route, the confirmation of each mode, the
/// destination, and "Connect when Jerd opens".
@Suite("Tunnel editor routes")
@MainActor
struct TunnelEditorRouteTests {
    private func filledDraft() -> TunnelEditorModel {
        let editor = TunnelEditorModel(tunnel: nil, sites: [SampleData.studio], suggestedPort: 20_243)
        editor.name = "Preview"
        editor.hostname = "preview.example.com"
        editor.token = "token"
        return editor
    }

    /// Jerd never publishes an address that the user did not enter.
    @Test("A new draft uses a Jerd route with no destination and no confirmation")
    func aNewDraftStartsWithoutADestination() {
        let editor = filledDraft()
        #expect(editor.routing == .local)
        #expect(editor.originURL.isEmpty)
        #expect(!editor.routeChecked)
        #expect(!editor.canSave)
        #expect(editor.validationMessage == nil)
    }

    /// A dashboard tunnel ignores a Jerd route, and a dashboard route can point anywhere, so a
    /// confirmation of one mode does not count for the other.
    @Test("Each route mode needs its own confirmation")
    func eachModeNeedsItsOwnConfirmation() {
        let editor = filledDraft()
        editor.siteID = SampleData.studio.id
        editor.routeChecked = true
        #expect(editor.canSave)
        editor.routing = .cloudflare
        #expect(!editor.routeChecked)
        #expect(editor.routeCheckTitle == "I checked the existing route for this Mac.")
        editor.routeChecked = true
        #expect(editor.canSave)
        editor.routing = .local
        #expect(!editor.routeChecked)
        #expect(editor.routeCheckTitle == "I checked that this tunnel is locally managed.")
    }

    @Test("A Jerd route to a site never connects when Jerd opens")
    func aJerdRouteToASiteNeverConnectsAtLaunch() {
        let editor = filledDraft()
        editor.connectsOnLaunch = true
        editor.siteID = SampleData.studio.id
        #expect(!editor.canConnectOnLaunch)
        #expect(!editor.connectsOnLaunch)
        #expect(editor.registration?.startOnLaunch == false)
        editor.siteID = nil
        editor.originURL = TunnelEditorModel.defaultOrigin
        #expect(editor.connectsOnLaunch)
        #expect(editor.registration?.startOnLaunch == true)
    }

    @Test("A Cloudflare route needs no local address")
    func aCloudflareRouteNeedsNoAddress() {
        let editor = filledDraft()
        editor.routing = .cloudflare
        editor.routeChecked = true
        #expect(editor.canSave)
        #expect(editor.registration?.originURL == nil)
    }

    @Test("A local address with a path shows the rule inline")
    func aLocalAddressWithAPathShowsTheRule() {
        let editor = filledDraft()
        editor.originURL = "http://127.0.0.1:8000/app"
        #expect(editor.validationMessage == TunnelMessage.localAddressPath)
        #expect(!editor.canSave)
        editor.routing = .cloudflare
        #expect(editor.validationMessage == nil)
    }

    @Test("The route copy names who sets the route, and only the editor names the restart")
    func theRouteCopyMatchesTheMode() {
        #expect(TunnelRouteCopy.setter(.local) == "Jerd")
        #expect(TunnelRouteCopy.setter(.cloudflare) == "Cloudflare dashboard")
        #expect(TunnelRouteCopy.editorFooter(.local, linksSite: true).contains("restarts all sites"))
        #expect(!TunnelRouteCopy.pageFooter(.local, linksSite: true).contains("restarts"))
        #expect(
            TunnelRouteCopy.editorFooter(.local, linksSite: false)
                == TunnelRouteCopy.pageFooter(.local, linksSite: false))
        #expect(TunnelRouteCopy.pageFooter(.cloudflare, linksSite: true).contains("for reference only"))
    }

    @Test("Connect names the local destination of a Jerd route")
    func connectNamesTheDestination() {
        let local = TunnelConfirmation.connect(SampleData.previewTunnel, destination: "https://studio.test")
        #expect(
            local.message
                == "Jerd will send https://preview.example.com to https://studio.test. Cloudflare can also send this traffic to other connectors of this tunnel."
        )
        let unknown = TunnelConfirmation.connect(SampleData.previewTunnel)
        #expect(unknown.message.contains("to the local destination of this tunnel."))
        #expect(
            TunnelConfirmation.connect(SampleData.docsTunnel).message.hasPrefix("Jerd will start another connector"))
    }
}

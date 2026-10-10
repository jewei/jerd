import JerdDesign
import JerdTunnels
import SwiftUI

/// Who sets the route, and its local destination.
struct TunnelDestinationSection: View {
    let state: AppState
    let sites: SitesModel
    let tunnel: TunnelRegistration

    var body: some View {
        Section {
            ValueRow(TunnelRouteCopy.label, value: TunnelRouteCopy.setter(tunnel.routing))
            destination
            ActionRow("Public hostname", detail: "In Cloudflare, this hostname must point to this tunnel.") {
                Button("Open Cloudflare", systemImage: "arrow.up.right") { sites.tunnels.openCloudflare() }
            }
        } header: {
            Text("Destination")
        } footer: {
            FormFooter(TunnelRouteCopy.pageFooter(tunnel.routing, linksSite: tunnel.siteID != nil))
        }
    }

    @ViewBuilder private var destination: some View {
        if let siteID = tunnel.siteID {
            if let site = sites.site(siteID) {
                ActionRow("Jerd site", detail: site.displayName) {
                    Button("View Site") { state.navigation.show(.item(.site(site.id))) }
                }
                ValueRow("Local address", value: "https://\(site.hostname)", isCode: true)
                ValueRow(
                    "Site environment", value: sites.environment.siteIDs.contains(site.id) ? "Running" : "Not running")
            } else if !sites.isLoaded {
                ValueRow("Jerd site", value: "Unavailable until the site settings load")
            } else {
                InlineMessage(TunnelMessage.siteRemoved, kind: .warning, identifier: "tunnel.site-removed")
            }
        } else {
            ValueRow("Local address", value: tunnel.originURL ?? "Not set", isCode: true)
        }
    }
}

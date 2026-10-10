import JerdDesign
import JerdTunnels
import SwiftUI

/// The local route, or a reference for a route managed in Cloudflare.
struct TunnelDestinationSection: View {
    let state: AppState
    let sites: SitesModel
    let tunnel: TunnelRegistration

    var body: some View {
        Section {
            ValueRow("Route managed by", value: tunnel.routing == .local ? "Jerd" : "Cloudflare")
            destination
            ActionRow("Cloudflare", detail: "The public hostname must point to this tunnel.") {
                Button("Open Cloudflare", systemImage: "arrow.up.right") { sites.tunnels.openCloudflare() }
            }
        } header: {
            Text(tunnel.routing == .local ? "Destination" : "Destination Reference")
        } footer: {
            FormFooter(
                tunnel.routing == .local
                    ? "Jerd configures this connector's route and verifies the site's HTTPS certificate."
                    : "Cloudflare manages this route. For a locally managed tunnel, select Jerd under Manage route in when you edit it."
            )
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
                InlineMessage(
                    "The linked site was removed. Edit this registration to select a destination.", kind: .warning,
                    identifier: "tunnel.site-removed")
            }
        } else {
            ValueRow("Local address", value: tunnel.originURL ?? "Not set", isCode: true)
        }
    }
}

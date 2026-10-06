import JerdDesign
import JerdTunnels
import SwiftUI

/// Where the Cloudflare route should point: a Jerd site or a local address. Only a reference;
/// Jerd never changes routes or DNS.
struct TunnelDestinationSection: View {
    let state: AppState
    let sites: SitesModel
    let tunnel: TunnelRegistration

    var body: some View {
        Section {
            destination
            ActionRow("Cloudflare route", detail: "Check the published hostname and origin in Cloudflare.") {
                Button("Open Cloudflare", systemImage: "arrow.up.right") { sites.tunnels.openCloudflare() }
            }
        } header: {
            Text("Destination Reference")
        } footer: {
            FormFooter(
                "Jerd does not change DNS or tunnel routes. For local HTTPS, keep TLS verification on and configure the trusted CA and origin hostname in Cloudflare."
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

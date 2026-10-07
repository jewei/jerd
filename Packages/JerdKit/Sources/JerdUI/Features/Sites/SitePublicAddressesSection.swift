import JerdDesign
import JerdTunnels
import JerdWeb
import SwiftUI

/// The tunnels whose route points to this site. Hidden when none does.
struct SitePublicAddressesSection: View {
    let state: AppState
    let model: SitesModel
    let site: Site

    var body: some View {
        let linked = model.tunnels.registrations.filter { $0.siteID == site.id }
        if !linked.isEmpty {
            Section("Public Addresses") {
                ForEach(linked) { tunnel in
                    ActionRow(tunnel.hostname, detail: model.tunnels.state(of: tunnel.id).title) {
                        Button("Copy URL") { model.tunnels.copyAddress(tunnel) }
                            .accessibilityLabel("Copy URL of \(tunnel.hostname)")
                        Button("View Tunnel") { state.navigation.show(.item(.tunnel(tunnel.id))) }
                            .accessibilityLabel("View tunnel \(tunnel.name)")
                    }
                }
            }
        }
    }
}

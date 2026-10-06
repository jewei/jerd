import JerdDesign
import SwiftUI

/// The Add menu (site or tunnel) and the counts. A separate view, so the shell can move it.
struct SitesSidebarFooter: View {
    let model: SitesModel

    var body: some View {
        SidebarFooter(addTitle: "Add Site or Tunnel", caption: caption) {
            Button("Add Site…", systemImage: "globe") { model.beginAdd() }
                .disabled(!model.canChange)
            Button("Add Cloudflare Tunnel…", systemImage: "network") {
                model.tunnels.beginAdd(sites: model.sites)
            }
            .disabled(!model.tunnels.canChange)
        }
        .accessibilityIdentifier("sites.add-menu")
    }

    private var caption: String? {
        let count = model.sites.count
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? "site" : "sites") · \(model.environment.siteIDs.count) running"
    }
}

import JerdDesign
import SwiftUI

/// The Add menu (site or tunnel) and the counts. A separate view, so the shell can move it.
struct SitesSidebarFooter: View {
    let model: SitesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        SidebarFooter(addTitle: "Add Site or Tunnel", caption: caption) {
            Button("Add Site…", systemImage: "globe") { model.beginAdd() }
                .disabled(!(model.canChange && !isQuitting))
            Button("Add Cloudflare Tunnel…", systemImage: "network") {
                model.tunnels.beginAdd(sites: model.sites)
            }
            .disabled(!(model.tunnels.canChange && !isQuitting))
        }
        .accessibilityIdentifier("sites.add-menu")
    }

    private var caption: String? {
        SidebarCaption.text(
            count: model.sites.count, singular: "site", plural: "sites", running: model.environment.siteIDs.count)
    }
}

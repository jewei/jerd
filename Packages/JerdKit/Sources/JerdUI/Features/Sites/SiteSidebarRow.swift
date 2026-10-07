import JerdDesign
import JerdWeb
import SwiftUI

/// One site in the sidebar, with its status and a context menu.
struct SiteSidebarRow: View {
    let model: SitesModel
    let site: Site

    var body: some View {
        SidebarRow(
            site.displayName, subtitle: site.hostname,
            status: SiteStatusPolicy.site(site, environment: model.environment, isWorking: model.isBusy),
            isDimmed: !site.isEnabled
        )
        .accessibilityIdentifier(AccessibilityIdentifier.make("sidebar", "site", site.hostname))
        .contextMenu {
            SiteRunButton(model: model, site: site)
            Divider()
            Button("Open in Browser", systemImage: "safari") { model.openInBrowser(site) }
                .disabled(!model.environment.siteIDs.contains(site.id))
            Button("Copy URL", systemImage: "doc.on.doc") { model.copyAddress(site) }
            Button("Show in Finder", systemImage: "folder") { model.revealProject(site) }
            Divider()
            Button("Edit Site…") { model.beginEdit(site) }
                .disabled(!model.canChange)
        }
    }
}

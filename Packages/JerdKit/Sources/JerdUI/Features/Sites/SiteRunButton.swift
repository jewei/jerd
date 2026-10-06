import JerdWeb
import SwiftUI

/// Start Site or Stop Site for one site. Start ends with "…" when the site still needs HTTPS
/// approval, because it then opens the approval sheet.
struct SiteRunButton: View {
    let model: SitesModel
    let site: Site

    var body: some View {
        if model.environment.siteIDs.contains(site.id) {
            Button("Stop Site", systemImage: "stop.fill") { model.stop(site) }
                .disabled(!model.canChange)
        } else {
            Button(SiteRunButton.startTitle(model: model, site: site), systemImage: "play.fill") { model.start(site) }
                .disabled(!model.canStart || !site.isEnabled)
        }
    }

    @MainActor
    static func startTitle(model: SitesModel, site: Site) -> String {
        model.isApproved(site) ? "Start Site" : "Start Site…"
    }
}

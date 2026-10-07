import JerdDesign
import JerdWeb
import SwiftUI

/// The project of a site: its folders, address, PHP selection, and web logs.
struct SiteProjectSection: View {
    let model: SitesModel
    let site: Site

    var body: some View {
        Section("Project") {
            PathRow("Project folder", path: site.projectPath) { model.revealProject(site) }
            PathRow("Document root", path: site.documentRoot) { model.revealDocumentRoot(site) }
            ValueRow("Address", value: "https://\(site.hostname)", isCode: true) { model.copyAddress(site) }
            ValueRow("PHP", value: PHPChoice.summary(for: site, in: model.configuration))
            ActionRow("Web logs", detail: "PHP-FPM and Caddy logs of all sites.") {
                Button("Open Logs", systemImage: "doc.text") { model.openLogs() }
                    .accessibilityIdentifier("site.open-logs")
            }
        }
    }
}

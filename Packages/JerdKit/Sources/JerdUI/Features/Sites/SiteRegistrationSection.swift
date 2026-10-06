import JerdDesign
import JerdWeb
import SwiftUI

/// Whether Start All includes the site, and the removal of its registration.
struct SiteRegistrationSection: View {
    let model: SitesModel
    let site: Site

    var body: some View {
        Section {
            ActionRow(
                "Site availability",
                detail: site.isEnabled ? "Included when you start all sites." : "Excluded when you start all sites."
            ) {
                Button(site.isEnabled ? "Disable Site" : "Enable Site") { model.setEnabled(site, !site.isEnabled) }
                    .disabled(!model.canChange)
                    .accessibilityIdentifier("site.toggle-enabled")
            }
            ActionRow("Registration", detail: "Keep the project folder and its files.") {
                Button("Remove Registration…", role: .destructive) { model.requestRemoval(site) }
                    .disabled(!model.canChange)
                    .accessibilityIdentifier("site.remove")
            }
        } footer: {
            FormFooter(
                "Removing a registration never deletes the project folder. Use trusted local projects only. Jerd does not isolate project code from your user account."
            )
        }
    }
}

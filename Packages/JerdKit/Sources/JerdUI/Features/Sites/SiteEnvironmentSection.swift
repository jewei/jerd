import JerdDesign
import SwiftUI

/// The commands for every site, last on a site page. The status shows once, in the header;
/// this row only counts the running sites. While site work can stop, the operation banner
/// owns Stop All Sites, so the row does not repeat it.
struct SiteEnvironmentSection: View {
    let model: SitesModel

    var body: some View {
        Section {
            ActionRow("Enabled sites", detail: detail) {
                Button(model.startAllTitle, systemImage: "play.fill") { model.startAll() }
                    .disabled(!model.canChange || !model.hasStoppedEnabledSite)
                    .accessibilityIdentifier("sites.start-all")
                if model.showsStopAllOnPage {
                    Button("Stop All Sites", systemImage: "stop.fill") { model.stopAll() }
                        .disabled(!model.canStopAll)
                        .accessibilityIdentifier("sites.stop-all")
                }
            }
        } header: {
            Text("All Sites")
        } footer: {
            FormFooter(
                "Start All Sites includes every enabled site. Ready means that PHP-FPM and HTTPS passed their checks. Jerd does not check project code. Changes restart the shared PHP and HTTPS services for a moment."
            )
        }
    }

    private var detail: String {
        "\(model.environment.siteIDs.count) of \(model.enabledSiteIDs.count) running"
    }
}

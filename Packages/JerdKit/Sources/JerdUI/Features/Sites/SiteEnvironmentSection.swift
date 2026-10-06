import JerdDesign
import SwiftUI

/// The shared environment: Start All Sites and Stop All Sites. The status shows once, in the
/// header of the page; this row explains it.
struct SiteEnvironmentSection: View {
    let model: SitesModel

    var body: some View {
        Section {
            ActionRow("Environment", detail: detail) {
                Button("Start All Sites", systemImage: "play.fill") { model.startAll() }
                    .disabled(!model.canStart || !model.hasStoppedEnabledSite)
                    .accessibilityIdentifier("sites.start-all")
                if model.canStopAll {
                    Button("Stop All Sites", systemImage: "stop.fill") { model.stopAll() }
                        .accessibilityIdentifier("sites.stop-all")
                }
            }
        } header: {
            Text("All Sites")
        } footer: {
            FormFooter(
                "Start All includes every enabled site. Ready means that PHP-FPM and HTTPS passed their checks; project code is not checked. Changes briefly restart the shared PHP and HTTPS services."
            )
        }
    }

    private var detail: String {
        let status = SiteStatusPolicy.overall(model.environment, isWorking: model.isBusy).label
        return "\(status) · \(model.environment.siteIDs.count) of \(model.enabledSiteIDs.count) enabled sites running"
    }
}

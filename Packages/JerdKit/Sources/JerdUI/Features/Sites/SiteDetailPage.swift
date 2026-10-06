import JerdDesign
import JerdWeb
import SwiftUI

/// The page of one site: its status, the next step, the shared environment, the project,
/// public addresses, connection checks, and its registration.
struct SiteDetailPage: View {
    let state: AppState
    let model: SitesModel
    let site: Site

    var body: some View {
        FormPage {
            PageHeader(
                site.displayName, subtitle: "https://\(site.hostname)",
                status: NamedStatus("Site status", status), primaryAction: primaryAction,
                secondaryActions: secondaryActions
            ) {
                SystemSetupMenu(model: model)
            }
        } messages: {
            SitesMessages(state: state, model: model)
        } content: {
            SiteEnvironmentSection(model: model)
            SiteProjectSection(model: model, site: site)
            SitePublicAddressesSection(state: state, model: model, site: site)
            SiteChecksSection(model: model, site: site)
            SiteRegistrationSection(model: model, site: site)
        }
    }

    private var status: DisplayStatus {
        SiteStatusPolicy.site(site, environment: model.environment, isWorking: model.isBusy)
    }

    private var isServed: Bool { model.environment.siteIDs.contains(site.id) }

    /// The next step: Open in Browser while the site runs, else Start Site.
    private var primaryAction: PageAction {
        if isServed {
            return PageAction("Open in Browser", systemImage: "safari", identifier: "site.open") {
                model.openInBrowser(site)
            }
        }
        return PageAction(
            SiteRunButton.startTitle(model: model, site: site), systemImage: "play.fill",
            isEnabled: model.canStart && site.isEnabled,
            help: site.isEnabled ? nil : "Enable this site before starting it.", identifier: "site.start"
        ) {
            model.start(site)
        }
    }

    private var secondaryActions: [PageAction] {
        var actions = [
            PageAction("Edit Site…", isEnabled: model.canChange, identifier: "site.edit") { model.beginEdit(site) }
        ]
        if isServed {
            actions.append(
                PageAction("Stop Site", systemImage: "stop.fill", isEnabled: model.canChange, identifier: "site.stop") {
                    model.stop(site)
                })
        }
        return actions
    }
}

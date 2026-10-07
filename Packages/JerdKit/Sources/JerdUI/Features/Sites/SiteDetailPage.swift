import JerdDesign
import JerdWeb
import SwiftUI

/// The page of one site: its status, the next step, the project, public addresses, connection
/// checks, its registration, and last the commands for all sites.
struct SiteDetailPage: View {
    let state: AppState
    let model: SitesModel
    let site: Site

    var body: some View {
        FormPage {
            PageHeader(
                site.displayName, subtitle: "https://\(site.hostname)",
                status: NamedStatus("Site status", status), primaryAction: primaryAction,
                secondaryActions: secondaryActions)
        } messages: {
            SitesMessages(model: model)
        } content: {
            SiteProjectSection(model: model, site: site)
            SitePublicAddressesSection(state: state, model: model, site: site)
            SiteChecksSection(model: model, site: site)
            SiteRegistrationSection(model: model, site: site)
            SiteEnvironmentSection(model: model)
        }
    }

    private var status: DisplayStatus {
        SiteStatusPolicy.site(site, environment: model.environment, isWorking: model.isBusy)
    }

    private var isServed: Bool { model.environment.siteIDs.contains(site.id) }

    /// The next step: Open Advanced while a recovery waits, Open in Browser while the site
    /// runs, else Start Site.
    private var primaryAction: PageAction {
        let step = model.nextStep(for: site)
        switch step {
        case .recover:
            return PageAction(step.title, systemImage: step.systemImage, identifier: "site.open-advanced") {
                model.openAdvanced()
            }
        case .open:
            return PageAction(step.title, systemImage: step.systemImage, identifier: "site.open") {
                model.openInBrowser(site)
            }
        case .start:
            return PageAction(
                step.title, systemImage: step.systemImage, isEnabled: model.canChange && site.isEnabled,
                help: site.isEnabled ? nil : "Enable this site before starting it.", identifier: "site.start"
            ) {
                model.start(site)
            }
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

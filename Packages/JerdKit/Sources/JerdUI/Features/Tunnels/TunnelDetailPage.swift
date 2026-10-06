import JerdDesign
import JerdTunnels
import SwiftUI

/// The page of one tunnel: its connector state, the next step, the public address, the
/// destination reference, startup, diagnostics, and its registration.
struct TunnelDetailPage: View {
    let state: AppState
    let sites: SitesModel
    let tunnel: TunnelRegistration
    @Environment(\.isQuitting) private var isQuitting

    private var model: TunnelsModel { sites.tunnels }

    var body: some View {
        FormPage {
            PageHeader(
                tunnel.name, subtitle: "https://\(tunnel.hostname)",
                status: NamedStatus("Tunnel status", TunnelStatusPolicy.status(model.state(of: tunnel.id))),
                primaryAction: primaryAction, secondaryActions: secondaryActions)
        } messages: {
            TunnelMessages(model: model, sites: sites, tunnel: tunnel)
        } content: {
            TunnelConnectionSection(model: model, tunnel: tunnel)
            TunnelDestinationSection(state: state, sites: sites, tunnel: tunnel)
            TunnelStartupSection(tunnel: tunnel)
            TunnelDiagnosticsSection(state: state, model: model, tunnel: tunnel)
            TunnelRegistrationSection(model: model, sites: sites, tunnel: tunnel)
        }
    }

    private var isActive: Bool { model.isActive(tunnel.id) }

    /// The next step: Open in Browser while the connector runs, Edit Tunnel… after a failure or
    /// with settings that need an edit, else Connect…. When a banner already offers Edit
    /// Tunnel…, the header has no primary action, so the page shows Edit Tunnel… once.
    private var primaryAction: PageAction? {
        switch model.nextStep(for: tunnel.id) {
        case .open:
            PageAction("Open in Browser", systemImage: "safari", identifier: "tunnel.open") {
                model.openInBrowser(tunnel)
            }
        case .edit where model.bannerOffersEdit(for: tunnel.id):
            nil
        case .edit:
            PageAction(
                TunnelNextStep.edit.title, systemImage: "pencil", isEnabled: model.canChange && !isQuitting,
                identifier: "tunnel.edit-primary"
            ) {
                model.beginEdit(tunnel, sites: sites.sites)
            }
        case .connect:
            connectAction
        }
    }

    private var connectAction: PageAction {
        PageAction(
            TunnelNextStep.connect.title, systemImage: "play.fill",
            isEnabled: (model.canChange && !isQuitting) && model.configuration.runtime != nil,
            help: model.configuration.runtime == nil ? model.runtimeMessage : nil, identifier: "tunnel.connect"
        ) {
            model.confirmation = .connect(tunnel)
        }
    }

    private var secondaryActions: [PageAction] {
        switch model.nextStep(for: tunnel.id) {
        case .open:
            [
                PageAction(
                    "Stop Connector", systemImage: "stop.fill", isEnabled: model.canStop(tunnel.id),
                    identifier: "tunnel.stop"
                ) {
                    model.stop(tunnel)
                }
            ]
        case .edit: [connectAction]
        case .connect: []
        }
    }
}

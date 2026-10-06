import JerdDesign
import JerdTunnels
import SwiftUI

/// The page of one tunnel: its connector state, the next step, the public address, the
/// destination reference, startup, diagnostics, and its registration.
struct TunnelDetailPage: View {
    let state: AppState
    let sites: SitesModel
    let tunnel: TunnelRegistration

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

    /// The next step: Open in Browser while the connector runs, else Connect.
    private var primaryAction: PageAction {
        if isActive {
            return PageAction("Open in Browser", systemImage: "safari", identifier: "tunnel.open") {
                model.openInBrowser(tunnel)
            }
        }
        return PageAction(
            "Connect…", systemImage: "play.fill", isEnabled: model.canChange && model.configuration.runtime != nil,
            help: model.configuration.runtime == nil ? model.runtimeMessage : nil, identifier: "tunnel.connect"
        ) {
            model.confirmation = .connect(tunnel)
        }
    }

    private var secondaryActions: [PageAction] {
        guard isActive else { return [] }
        return [
            PageAction(
                "Stop Connector", systemImage: "stop.fill", isEnabled: model.canStop(tunnel.id), identifier: "tunnel.stop"
            ) {
                model.stop(tunnel)
            }
        ]
    }
}

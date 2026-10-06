import JerdDesign
import JerdTunnels
import SwiftUI

/// One tunnel in the Sites sidebar, with its connector state and a context menu.
struct TunnelSidebarRow: View {
    let model: TunnelsModel
    let tunnel: TunnelRegistration

    var body: some View {
        SidebarRow(
            tunnel.name, subtitle: tunnel.hostname, status: TunnelStatusPolicy.status(model.state(of: tunnel.id))
        )
        .accessibilityIdentifier(AccessibilityIdentifier.make("sidebar", "tunnel", tunnel.hostname))
        .contextMenu {
            Button("Open in Browser", systemImage: "safari") { model.openInBrowser(tunnel) }
            Button("Copy URL", systemImage: "doc.on.doc") { model.copyAddress(tunnel) }
        }
    }
}

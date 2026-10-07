import JerdDesign
import JerdTunnels
import SwiftUI

/// Edit and Remove of a tunnel registration. Both need a stopped connector.
struct TunnelRegistrationSection: View {
    let model: TunnelsModel
    @Environment(\.isQuitting) private var isQuitting
    let sites: SitesModel
    let tunnel: TunnelRegistration

    var body: some View {
        let isActive = model.isActive(tunnel.id)
        Section {
            ActionRow("Settings", detail: "Edit the token, destination reference, or startup settings.") {
                Button("Edit Tunnel…") { model.beginEdit(tunnel, sites: sites.sites) }
                    .disabled(!(model.canChange && !isQuitting) || isActive)
                    .accessibilityIdentifier("tunnel.edit")
            }
            ActionRow("Registration", detail: "Keep the Cloudflare tunnel and DNS settings.") {
                Button("Remove Registration…", role: .destructive) { model.confirmation = .remove(tunnel) }
                    .disabled(!(model.canChange && !isQuitting))
                    .accessibilityIdentifier("tunnel.remove")
            }
        } footer: {
            if isActive {
                FormFooter("Stop this connector before you edit its settings.")
            }
        }
    }
}

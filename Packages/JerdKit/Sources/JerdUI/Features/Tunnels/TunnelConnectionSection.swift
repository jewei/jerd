import JerdDesign
import JerdTunnels
import SwiftUI

/// The public address and what "Connected" means. Jerd only looks up the public hostname in DNS
/// and never calls it, so the page shows no website health result.
struct TunnelConnectionSection: View {
    let model: TunnelsModel
    let tunnel: TunnelRegistration

    var body: some View {
        Section {
            ValueRow("Public address", value: "https://\(tunnel.hostname)", isCode: true) { model.copyAddress(tunnel) }
            ValueRow("Metrics endpoint", value: "127.0.0.1:\(tunnel.metricsPort)", isCode: true)
        } header: {
            Text("Connection")
        } footer: {
            FormFooter(
                "Connected means that Cloudflare accepts this connector. It does not confirm that your website responds. Jerd checks only that the public address has a DNS record. Other connectors can also serve this address."
            )
        }
    }
}

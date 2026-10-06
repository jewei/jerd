import JerdDesign
import SwiftUI

/// The Sites page without sites and tunnels, or before the sites are loaded.
struct SitesEmptyState: View {
    let model: SitesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        if !model.isLoaded, let failure = model.operation.failureMessage {
            EmptyState("Sites Could Not Load", systemImage: "exclamationmark.triangle", message: failure) {
                Button("Retry Load", systemImage: "arrow.clockwise") { model.retryLoad() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sites.retry-load")
            }
        } else {
            EmptyState(
                "A Home for Your Local Sites", systemImage: "globe.desk",
                message:
                    "Serve a local PHP project over HTTPS, or connect an existing Cloudflare tunnel. Your project files stay where they are."
            ) {
                Button("Add Your First Site…", systemImage: "plus") { model.beginAdd() }
                    .primaryActionStyle(isEnabled: (model.canChange && !isQuitting))
                    .accessibilityIdentifier("sites.add-first")
                Button("Add Cloudflare Tunnel…", systemImage: "network") {
                    model.tunnels.beginAdd(sites: model.sites)
                }
                .disabled(!(model.tunnels.canChange && !isQuitting))
                .accessibilityIdentifier("sites.add-tunnel")
            }
        }
    }
}

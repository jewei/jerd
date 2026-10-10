import Foundation
import JerdDesign
import JerdTunnels
import SwiftUI

/// The local destination that the Cloudflare route should use: a Jerd site or an address.
struct TunnelEditorDestinationSection: View {
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        Section {
            Picker("Manage route in", selection: $editor.routing) {
                Text("Jerd (locally managed tunnel)").tag(TunnelRouting.local)
                Text("Cloudflare dashboard").tag(TunnelRouting.cloudflare)
            }
            Picker("Local destination", selection: $editor.siteID) {
                Text("Local HTTP or HTTPS address").tag(UUID?.none)
                ForEach(editor.sites) { site in
                    Text(site.displayName).tag(UUID?.some(site.id))
                }
                if editor.isSiteMissing {
                    Text("Removed site — choose a destination").tag(editor.siteID)
                }
            }
            if let siteID = editor.siteID, let site = editor.sites.first(where: { $0.id == siteID }) {
                ValueRow("Local address", value: "https://\(site.hostname)", isCode: true)
            } else if editor.siteID == nil {
                TextField("Local address", text: $editor.originURL, prompt: Text(TunnelEditorModel.defaultOrigin))
            }
        } header: {
            Text(editor.routing == .local ? "Destination" : "Destination Reference")
        } footer: {
            FormFooter(
                editor.routing == .local
                    ? "Jerd configures the local route and HTTPS when you connect. Applying a changed route briefly restarts the shared web services."
                    : "Match this reference to the route in Cloudflare. Use Jerd for a locally managed tunnel."
            )
        }
    }
}

import Foundation
import JerdDesign
import SwiftUI

/// The local destination that the Cloudflare route should use: a Jerd site or an address.
struct TunnelEditorDestinationSection: View {
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        Section {
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
            Text("Destination Reference")
        } footer: {
            FormFooter(
                "Match this reference to the route in Cloudflare. Saving here does not change DNS, routing, or TLS settings."
            )
        }
    }
}

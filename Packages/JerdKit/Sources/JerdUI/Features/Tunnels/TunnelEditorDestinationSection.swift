import Foundation
import JerdDesign
import JerdTunnels
import SwiftUI

/// Who sets the route, and its local destination: a Jerd site or an address.
struct TunnelEditorDestinationSection: View {
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        Section {
            Picker(TunnelRouteCopy.label, selection: $editor.routing) {
                ForEach(TunnelRouting.allCases, id: \.self) { routing in
                    Text(TunnelRouteCopy.setter(routing)).tag(routing)
                }
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
            Text("Destination")
        } footer: {
            FormFooter(TunnelRouteCopy.editorFooter(editor.routing, linksSite: editor.siteID != nil))
        }
    }
}

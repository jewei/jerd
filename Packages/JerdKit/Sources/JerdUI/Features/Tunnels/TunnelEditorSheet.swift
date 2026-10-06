import JerdDesign
import SwiftUI

/// Add or edit the registration of an existing Cloudflare tunnel. Save never connects.
struct TunnelEditorSheet: View {
    let model: TunnelsModel
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        SheetScaffold(
            editor.title, message: "Connect an existing tunnel to this Mac. Save adds the registration; it does not connect.",
            size: .wide,
            confirmation: SheetConfirmation(
                "Save Registration", isEnabled: editor.canSave && model.canChange, identifier: "tunnel-editor"
            ) {
                model.save(editor)
            },
            workingMessage: model.operation.workingMessage, cancel: model.cancelEditor
        ) {
            TunnelEditorTunnelSection(editor: editor)
            TunnelEditorDestinationSection(editor: editor)
            Section("Startup") {
                Toggle("Connect when Jerd opens", isOn: $editor.startOnLaunch)
                Toggle("Restart after an unexpected exit", isOn: $editor.restartOnFailure)
            }
            Section {
                Toggle("I checked the existing route for this Mac.", isOn: $editor.routeChecked)
                    .accessibilityIdentifier("tunnel-editor.route-checked")
                ActionRow(
                    "Cloudflare route",
                    detail: "Another connector can already serve this tunnel and share its traffic. Select Connect when you are ready."
                ) {
                    Button("Open Cloudflare", systemImage: "arrow.up.right") { model.openCloudflare() }
                }
            }
            if let message = editor.failure ?? editor.validationMessage {
                InlineMessage(message, kind: editor.failure == nil ? .warning : .error, identifier: "tunnel-editor.error")
            }
        }
    }
}

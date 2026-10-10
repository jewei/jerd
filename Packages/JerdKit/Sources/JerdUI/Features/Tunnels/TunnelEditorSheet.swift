import JerdDesign
import SwiftUI

/// Add or edit the registration of an existing Cloudflare tunnel. Save never connects.
struct TunnelEditorSheet: View {
    let model: TunnelsModel
    @Bindable var editor: TunnelEditorModel

    var body: some View {
        SheetScaffold(
            editor.title,
            message: "Connect an existing tunnel to this Mac. Save adds the registration; it does not connect.",
            size: .wide,
            confirmation: SheetConfirmation(
                "Save Registration", isEnabled: editor.canSave && model.canChange, identifier: "tunnel-editor"
            ) {
                model.save(editor)
            },
            workingMessage: model.operation.workingMessage, cancel: model.cancelEditor
        ) {
            SheetTopMessage(message: topMessage?.text, kind: topMessage?.kind ?? .info, identifier: topIdentifier)
            TunnelEditorTunnelSection(editor: editor)
            TunnelEditorDestinationSection(editor: editor)
            startup
            routeConfirmation
        }
    }

    private var startup: some View {
        Section {
            Toggle("Connect when Jerd opens", isOn: $editor.connectsOnLaunch)
                .disabled(!editor.canConnectOnLaunch)
            Toggle("Restart after an unexpected exit", isOn: $editor.restartOnFailure)
        } header: {
            Text("Startup")
        } footer: {
            if !editor.canConnectOnLaunch { FormFooter(TunnelRouteCopy.launchNote) }
        }
    }

    /// Save needs it in both route modes.
    private var routeConfirmation: some View {
        Section {
            Toggle(editor.routeCheckTitle, isOn: $editor.routeChecked)
                .accessibilityIdentifier("tunnel-editor.route-checked")
            ActionRow(TunnelRouteCopy.checkTitle(editor.routing), detail: TunnelRouteCopy.checkDetail(editor.routing)) {
                Button("Open Cloudflare", systemImage: "arrow.up.right") { model.openCloudflare() }
            }
        }
    }

    /// A failure first, then a broken rule, then why Save is off.
    private var topMessage: (text: String, kind: MessageKind)? {
        if let failure = editor.failure { return (failure, .error) }
        if let rule = editor.validationMessage { return (rule, .warning) }
        return editor.saveRequirement.map { ($0, .info) }
    }

    private var topIdentifier: String {
        editor.failure == nil && editor.validationMessage == nil ? "tunnel-editor.requirement" : "tunnel-editor.error"
    }
}

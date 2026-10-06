import JerdDesign
import SwiftUI

/// The document root, its suggestion, and its confirmation. A change of the folder or the
/// root clears the confirmation.
struct SiteEditorRootSection: View {
    @Bindable var editor: SiteEditorModel

    var body: some View {
        Section {
            LabeledContent("Document root") {
                HStack(spacing: Spacing.small) {
                    TextField("Document root", text: $editor.documentRoot, prompt: Text("/path/to/project/public"))
                        .labelsHidden()
                        .font(TextRole.path.font)
                    Button("Choose…") { Task { await editor.chooseDocumentRoot() } }
                        .accessibilityLabel("Choose document root")
                        .accessibilityIdentifier("site-editor.choose-root")
                }
            }
            ActionRow("Suggestion", detail: editor.suggestionText) {
                Button("Inspect Project") { Task { await editor.inspect() } }
                    .disabled(editor.projectPath.isEmpty || editor.isInspecting)
                    .accessibilityIdentifier("site-editor.inspect")
            }
            if editor.requiresConfirmation {
                Toggle("I confirm that this document root can be served.", isOn: $editor.isRootConfirmed)
                    .accessibilityIdentifier("site-editor.confirm-root")
            }
        } header: {
            Text("Document Root")
        } footer: {
            if editor.requiresConfirmation && !editor.isRootConfirmed {
                FormFooter(
                    "Confirm the document root to save. Every file below it can be requested. Changing the folder or document root clears the confirmation."
                )
            }
        }
    }
}

import JerdDesign
import SwiftUI

/// The project folder, the name, and the hostname of the site editor.
struct SiteEditorProjectSection: View {
    @Bindable var editor: SiteEditorModel

    var body: some View {
        Section("Project") {
            LabeledContent("Project folder") {
                HStack(spacing: Spacing.small) {
                    TextField("Project folder", text: $editor.projectPath, prompt: Text("/path/to/project"))
                        .labelsHidden()
                        .font(TextRole.path.font)
                    Button("Choose…") { Task { await editor.chooseProjectFolder() } }
                        .accessibilityLabel("Choose project folder")
                        .accessibilityIdentifier("site-editor.choose-project")
                }
            }
            TextField("Display name", text: $editor.displayName, prompt: Text("Studio"))
            TextField("Hostname", text: $editor.hostname, prompt: Text("project.test"))
            if let message = editor.hostnameMessage {
                InlineMessage(message, kind: .warning, identifier: "site-editor.hostname")
            }
        }
    }
}

import JerdDesign
import SwiftUI

/// Add Site and Edit Site. Cancel always closes the sheet and never stops other work.
struct SiteEditorSheet: View {
    let model: SitesModel
    @Bindable var editor: SiteEditorModel

    var body: some View {
        SheetScaffold(
            editor.title, message: "Detection reads files only. It does not run artisan or project scripts.",
            size: .wide,
            confirmation: SheetConfirmation(
                "Save Registration", isEnabled: editor.canSave && model.canChange, identifier: "site-editor"
            ) {
                model.save(editor)
            },
            workingMessage: model.operation.workingMessage ?? (editor.isInspecting ? "Inspecting the project…" : nil),
            cancel: model.cancelEditor
        ) {
            SiteEditorProjectSection(editor: editor)
            SiteEditorRootSection(editor: editor)
            Section("Runtime") {
                Picker("PHP selection", selection: $editor.phpSelection) {
                    ForEach(editor.phpChoices, id: \.selection) { choice in
                        Text(choice.title).tag(choice.selection)
                    }
                }
                Toggle("Include when starting all sites", isOn: $editor.isEnabled)
            }
            if let failure = editor.failure {
                InlineMessage(failure, kind: .error, identifier: "site-editor.error")
            }
        }
    }
}

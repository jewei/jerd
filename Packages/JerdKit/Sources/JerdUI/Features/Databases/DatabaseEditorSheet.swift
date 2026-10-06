import JerdDatabases
import JerdDesign
import SwiftUI

/// The Add and Edit Database sheet. Package access lets the snapshot catalog render it alone.
package struct DatabaseEditorSheet: View {
    @Bindable var model: DatabasesModel

    package init(model: DatabasesModel) {
        self.model = model
    }

    package var body: some View {
        SheetScaffold(
            draft.isAdding ? "Add Database" : "Edit Database", message: message,
            confirmation: SheetConfirmation(
                draft.isAdding ? "Create and Start" : "Save",
                isEnabled: draft.service(in: model.configuration) != nil && model.canChangeRegistry,
                identifier: "database-editor"
            ) { model.saveEditor() },
            workingMessage: model.editorOperation.workingMessage, cancel: model.closeEditor
        ) {
            Section {
                Picker("Engine", selection: engine) {
                    ForEach(model.availableEngines, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!draft.isAdding)
                Picker("Version", selection: runtimeID) {
                    ForEach(runtimes) { Text($0.version).tag(Optional($0.id)) }
                }
                .disabled(!draft.isAdding)
                TextField("Name", text: name)
                    .accessibilityIdentifier("database-editor.name")
                TextField("Port", text: port, prompt: Text(PortInput.prompt))
                    .accessibilityIdentifier("database-editor.port")
                if let issue = draft.issue(in: model.configuration) {
                    InlineMessage(issue, kind: .warning, identifier: "database-editor.issue")
                }
            } footer: {
                FormFooter("The service listens only on 127.0.0.1. Jerd suggests the first free port.")
            }
            if let failure = model.editorOperation.failureMessage {
                Section {
                    InlineMessage(failure, kind: .error, identifier: "database-editor.error")
                }
            }
        }
    }

    private var draft: DatabaseDraft { model.editor ?? .add(.mysql, in: model.configuration) }

    private var message: String {
        draft.isAdding
            ? "Jerd creates a separate data folder and password, then starts the service."
            : "The engine and version stay fixed because the data folder uses them."
    }

    private var runtimes: [DatabaseRuntime] {
        model.configuration.runtimes.filter { $0.engine == draft.engine }
    }

    private var engine: Binding<DatabaseEngine> {
        Binding {
            draft.engine
        } set: {
            model.changeEngine($0)
        }
    }

    private var runtimeID: Binding<String?> {
        Binding {
            draft.runtimeID
        } set: {
            model.editor?.runtimeID = $0
        }
    }

    private var name: Binding<String> {
        Binding {
            draft.name
        } set: {
            model.editor?.setName($0)
        }
    }

    private var port: Binding<String> {
        Binding {
            draft.portText
        } set: {
            model.editor?.setPort($0)
        }
    }
}

import JerdDatabases
import JerdDesign
import SwiftUI

/// The Add and Edit Database sheet. Package access lets the snapshot catalog render it alone.
package struct DatabaseEditorSheet: View {
    @Bindable var model: DatabasesModel
    @Environment(\.isQuitting) private var isQuitting

    package init(model: DatabasesModel) {
        self.model = model
    }

    package var body: some View {
        SheetScaffold(
            draft.isAdding ? "Add Database" : "Edit Database", message: message,
            confirmation: SheetConfirmation(
                draft.isAdding ? DatabaseRuntimeCopy.addTitle(installsRuntime: offer != nil) : "Save",
                isEnabled: model.canSaveEditor && !isQuitting, identifier: "database-editor"
            ) { model.saveEditor() },
            workingMessage: model.editorOperation.workingMessage, cancel: model.closeEditor
        ) {
            Section {
                Picker("Engine", selection: engine) {
                    ForEach(engines, id: \.self) { engine in
                        Text(
                            DatabaseRuntimeCopy.engineLabel(
                                engine, isInstalled: model.availableEngines.contains(engine))
                        )
                        .tag(engine)
                    }
                }
                .disabled(!draft.isAdding || isInstalling)
                if let offer {
                    ValueRow("Version", value: offer.versionLabel)
                } else {
                    Picker("Version", selection: runtimeID) {
                        ForEach(runtimes) { Text($0.version).tag(Optional($0.id)) }
                    }
                    .disabled(!draft.isAdding)
                }
                TextField("Name", text: name)
                    .accessibilityIdentifier("database-editor.name")
                TextField("Port", text: port, prompt: Text(PortInput.prompt))
                    .accessibilityIdentifier("database-editor.port")
                if let issue = draft.issue(in: model.configuration, installsRuntime: offer != nil) {
                    InlineMessage(issue, kind: .warning, identifier: "database-editor.issue")
                }
            } footer: {
                FormFooter("The service listens only on 127.0.0.1. Jerd suggests the first free port.")
            }
            // After a failure, the error below replaces the note, so the sheet stays short.
            if let offer, model.editorOperation.failureMessage == nil {
                Section {
                    if let installation = model.runtimeInstallation, installation.addsService {
                        DatabaseRuntimeProgressRow(installation: installation, cancel: nil)
                    } else if let other = model.runtimeInstallation {
                        InlineMessage(
                            "Wait for the \(other.engine.title) installation to finish.", kind: .info,
                            identifier: "database-editor.install-waits")
                    } else {
                        InlineMessage(
                            DatabaseRuntimeCopy.addNote(offer), kind: .info, identifier: "database-editor.install-note")
                    }
                } header: {
                    Text("Runtime")
                }
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
        if let offer {
            return
                "Jerd installs \(offer.engine.title), creates a separate data folder and password, then starts the service."
        }
        return draft.isAdding
            ? "Jerd creates a separate data folder and password, then starts the service."
            : "The engine and version stay fixed because the data folder uses them."
    }

    /// The pinned runtime that Save installs first, or nil when the engine has a runtime.
    private var offer: DatabaseRuntimeOffer? { model.editorRuntimeOffer }

    private var isInstalling: Bool { model.runtimeInstallation?.addsService == true }

    /// Add lists every engine that it can create; Edit shows only the service's own engine.
    private var engines: [DatabaseEngine] { draft.isAdding ? model.addableEngines : [draft.engine] }

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

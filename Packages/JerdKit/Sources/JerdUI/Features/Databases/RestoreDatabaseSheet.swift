import Foundation
import JerdDatabases
import JerdDesign
import SwiftUI

/// A new name and port for retained data. Package access lets the snapshot catalog render it.
package struct RestoreDatabaseSheet: View {
    @Bindable var model: DatabasesModel

    package init(model: DatabasesModel) {
        self.model = model
    }

    package var body: some View {
        SheetScaffold(
            "Restore Database",
            message: "The original runtime and data folder stay in use. Start the service after you restore it.",
            confirmation: SheetConfirmation(
                "Restore", isEnabled: canRestore, identifier: "restore-database"
            ) { model.saveRestore() },
            workingMessage: model.restoreOperation.workingMessage, cancel: model.closeRestore
        ) {
            if let draft = model.restoreDraft {
                Section {
                    ValueRow("Runtime", value: runtimeText(draft.database))
                    TextField("Name", text: binding.name)
                        .accessibilityIdentifier("restore-database.name")
                    TextField("Port", text: binding.portText, prompt: Text(PortInput.prompt))
                        .accessibilityIdentifier("restore-database.port")
                    if let issue = draft.issue(in: model.configuration) {
                        InlineMessage(issue, kind: .warning, identifier: "restore-database.issue")
                    }
                }
            }
            if let failure = model.restoreOperation.failureMessage {
                Section {
                    InlineMessage(failure, kind: .error, identifier: "restore-database.error")
                }
            }
        }
    }

    private var canRestore: Bool {
        model.restoreDraft?.values(in: model.configuration) != nil && model.canChangeRegistry
    }

    private func runtimeText(_ database: RetainedDatabase) -> String {
        database.runtime.map { "\($0.engine.title) \($0.version)" } ?? "Runtime unavailable"
    }

    private var binding: Binding<RestoreDraft> {
        Binding {
            model.restoreDraft ?? RestoreDraft(database: placeholder)
        } set: { draft in
            model.restoreDraft = draft
        }
    }

    private var placeholder: RetainedDatabase {
        RetainedDatabase(
            id: UUID(), name: "", runtime: nil, port: nil, directory: URL(fileURLWithPath: "/"), bytes: nil,
            problem: nil)
    }
}

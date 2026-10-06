import Foundation
import JerdDatabases
import JerdDesign
import SwiftUI

/// The data folders of removed registrations, each with Restore… when Jerd can register it
/// again. Package access lets the snapshot catalog render it alone.
package struct RetainedDatabasesSheet: View {
    let model: DatabasesModel
    @Environment(\.isQuitting) private var isQuitting

    package init(model: DatabasesModel) {
        self.model = model
    }

    package var body: some View {
        SheetScaffold(
            "Retained Databases",
            message:
                "Restore a removed registration with its original runtime and data. Choose a name and a free port.",
            size: .wide,
            confirmation: Self.confirmation(model: model, isQuitting: isQuitting),
            workingMessage: model.retainedOperation.workingMessage, cancel: model.closeRetained
        ) {
            if let failure = model.retainedOperation.failureMessage {
                Section {
                    InlineMessage(failure, kind: .error, identifier: "retained-databases.error")
                }
            }
            if model.retained.isEmpty, !model.retainedOperation.isWorking {
                Section {
                    Text("No removed database registrations were found.")
                        .textRole(.detail)
                }
            }
            ForEach(model.retained) { database in
                Section {
                    row(database)
                }
            }
        }
    }

    /// The list is information, so Return closes it with Done (spec F 3.3); Inspect Again is
    /// the secondary button. Escape also closes it.
    static func confirmation(model: DatabasesModel, isQuitting: Bool) -> SheetConfirmation {
        SheetConfirmation(
            "Inspect Again", cancelTitle: "Done", isEnabled: !isQuitting, returnKey: .cancel,
            identifier: "retained-databases"
        ) { model.inspectRetained() }
    }

    @ViewBuilder
    private func row(_ database: RetainedDatabase) -> some View {
        ActionRow(database.name, detail: detail(database)) {
            Button("Restore…") { model.beginRestore(database) }
                .disabled(isQuitting || !database.canRestore || !model.canChangeRegistry)
                .accessibilityLabel("Restore \(database.name)")
                .accessibilityIdentifier(AccessibilityIdentifier.make("retained", "restore", database.name))
        }
        PathRow("Data folder", path: database.directory.path) {
            model.revealRetained(database)
        }
        if let problem = database.problem {
            InlineMessage(problem, kind: .warning)
        }
    }

    private func detail(_ database: RetainedDatabase) -> String {
        let runtime = database.runtime.map { "\($0.engine.title) \($0.version)" } ?? "Runtime unavailable"
        let size = database.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return [runtime, size].compactMap { $0 }.joined(separator: " · ")
    }
}

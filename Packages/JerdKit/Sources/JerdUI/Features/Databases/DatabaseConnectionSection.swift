import JerdDatabases
import JerdDesign
import SwiftUI

/// The connection values of one service, its password, and its Laravel settings.
struct DatabaseConnectionSection: View {
    let model: DatabasesModel
    let service: DatabaseService
    let engine: DatabaseEngine

    var body: some View {
        Section {
            value("Host", "127.0.0.1")
            value("Port", String(service.port))
            value("User", engine.username)
            value("Database", engine.database)
            ActionRow("Password", detail: hasStarted ? nil : "Created at the first start.") {
                Button("Copy Password", systemImage: "key") { model.copyPassword(service.id) }
                    .disabled(!hasStarted)
                    .accessibilityLabel("Copy \(service.name) password")
                    .accessibilityIdentifier("database.copy-password")
            }
        } header: {
            Text("Connection")
        } footer: {
            FormFooter("Available only on this Mac. Each service has its own password.")
        }
        Section {
            ActionRow(".env settings", detail: hasStarted ? nil : "Available after the first start.") {
                Button("Copy Laravel Settings", systemImage: "doc.on.doc") { model.copyEnvironment(service.id) }
                    .disabled(!hasStarted)
                    .accessibilityIdentifier("database.copy-laravel")
            }
        } header: {
            Text("Laravel")
        } footer: {
            FormFooter("Paste these settings into your application's .env file.")
        }
    }

    /// The password exists after the first start created the data folder.
    private var hasStarted: Bool { model.files[service.id]?.hasDataFolder == true }

    private func value(_ label: String, _ text: String) -> ValueRow {
        ValueRow(label, value: text, isCode: true) { model.copyValue(text, label: label) }
    }
}

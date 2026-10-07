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
            ForEach(Self.values(model, service: service, engine: engine)) { ConnectionValueRow(value: $0) }
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
                CopyLaravelSettingsButton(isEnabled: hasStarted, identifier: "database.copy-laravel") {
                    model.copyEnvironment(service.id)
                }
            }
        } header: {
            Text("Laravel")
        } footer: {
            FormFooter("Paste these settings into your application's .env file.")
        }
    }

    /// The password exists after the first start created the data folder.
    private var hasStarted: Bool { model.files[service.id]?.hasDataFolder == true }

    /// The host, port, user, and database name, each to paste.
    static func values(_ model: DatabasesModel, service: DatabaseService, engine: DatabaseEngine) -> [ConnectionValue] {
        [
            ("Host", "127.0.0.1"), ("Port", String(service.port)), ("User", engine.username),
            ("Database", engine.database),
        ]
        .map { label, text in .pasteable(label, text) { model.copyValue(text, label: label) } }
    }
}

import JerdDatabases
import JerdDesign
import SwiftUI

/// Edit and Remove of one registration. Remove always keeps the data.
struct DatabaseRegistrationSection: View {
    let model: DatabasesModel
    let service: DatabaseService
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        Section {
            ActionRow("Registration", detail: "Name and port. The engine and version stay fixed.") {
                Button("Edit Service…") { model.beginEdit(service.id) }
                    .disabled(isQuitting || !model.canEdit(service.id))
                    .accessibilityLabel("Edit \(service.name)")
                    .accessibilityIdentifier("database.edit")
                Button("Remove Registration…", role: .destructive) { model.requestRemove(service.id) }
                    .disabled(isQuitting || !model.canRemove(service.id))
                    .accessibilityLabel("Remove \(service.name) registration")
                    .accessibilityIdentifier("database.remove")
            }
        } header: {
            Text("Service")
        } footer: {
            // The Files section above already says that the data stays.
            if model.state(of: service.id).offersStop {
                FormFooter("Stop the service to change its name or port.")
            }
        }
    }
}

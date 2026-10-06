import JerdDatabases
import JerdDesign
import SwiftUI

/// A registered service whose runtime is not installed. Its data stays; it can be removed and
/// restored later with the right runtime.
struct DatabaseRuntimeMissingPage: View {
    let model: DatabasesModel
    let service: DatabaseService

    var body: some View {
        EmptyState(
            "Runtime Unavailable", systemImage: "exclamationmark.triangle",
            message: "\(service.name) uses a database runtime that is not installed. Its data folder stays in place."
        ) {
            Button("View Runtimes") { model.showRuntimes() }
                .primaryActionStyle(isEnabled: true)
            if model.files[service.id]?.hasDataFolder == true {
                Button("Show Data Folder") { model.revealData(service.id) }
            }
            Button("Remove Registration…", role: .destructive) { model.requestRemove(service.id) }
                .disabled(!model.canRemove(service.id))
        }
    }
}

import JerdDatabases
import JerdDesign
import SwiftUI

/// A registered service whose runtime is not installed. Its data stays; it can be removed and
/// restored later with the right runtime. A failed Remove and a service that did not stop show
/// once, at the top, as on the service page.
struct DatabaseRuntimeMissingPage: View {
    let model: DatabasesModel
    let service: DatabaseService
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.small) {
                DatabasesPageMessages(model: model, service: service)
            }
            .padding(.horizontal, Spacing.large)
            .padding(.top, Spacing.large)
            EmptyState(
                "Runtime Unavailable", systemImage: "exclamationmark.triangle",
                message:
                    "\(service.name) uses a database runtime that is not installed. Its data folder stays in place."
            ) {
                Button("View Runtimes") { model.showRuntimes() }
                    .primaryActionStyle(isEnabled: true)
                if model.files[service.id]?.hasDataFolder == true {
                    Button("Show Data Folder") { model.revealData(service.id) }
                }
                Button("Remove Registration…", role: .destructive) { model.requestRemove(service.id) }
                    .disabled(isQuitting || !model.canRemove(service.id))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

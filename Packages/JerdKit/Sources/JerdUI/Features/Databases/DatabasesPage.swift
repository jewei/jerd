import JerdDatabases
import JerdDesign
import SwiftUI

/// The detail of the Databases section: the selected service, a service whose runtime is
/// missing, or the empty state. It owns the sheets and the remove confirmation.
struct DatabasesPage: View {
    let state: AppState
    @Bindable var model: DatabasesModel

    var body: some View {
        content
            .sheet(item: $model.sheet, onDismiss: { model.dismissSheet() }) { sheet in
                switch sheet {
                case .editor: DatabaseEditorSheet(model: model)
                case .retained: RetainedDatabasesSheet(model: model)
                case .restore: RestoreDatabaseSheet(model: model)
                }
            }
            .confirmationDialog(
                "Remove this database registration?", isPresented: isConfirmingRemoval, titleVisibility: .visible,
                presenting: model.pendingRemoval
            ) { _ in
                Button("Remove Registration", role: .destructive) { model.confirmRemove() }
                Button("Cancel", role: .cancel) { model.pendingRemoval = nil }
            } message: { service in
                Text(
                    "Jerd stops \(service.name) and removes its registration. Its database files stay in the data folder, and Retained Databases can restore it."
                )
            }
    }

    @ViewBuilder private var content: some View {
        if let service = selectedService {
            if model.runtime(of: service) != nil {
                DatabaseDetailPage(model: model, service: service)
            } else {
                DatabaseRuntimeMissingPage(model: model, service: service)
            }
        } else {
            DatabasesEmptyPage(model: model)
        }
    }

    private var selectedService: DatabaseService? {
        guard case .database(let id) = state.navigation.selection(in: .databases) else { return nil }
        return model.service(id)
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding {
            model.pendingRemoval != nil
        } set: { isPresented in
            if !isPresented { model.pendingRemoval = nil }
        }
    }
}

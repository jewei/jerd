import JerdDatabases
import JerdDesign
import SwiftUI

/// The detail of the Databases section: the selected service, a service whose runtime is
/// missing, or the empty state. It owns the sheets and the remove confirmation.
struct DatabasesPage: View {
    let state: AppState
    let model: DatabasesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        content
            .sheet(item: SheetBinding.item({ model.sheet }, dismiss: model.dismissSheet)) { sheet in
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
                    .disabled(isQuitting)
                Button("Cancel", role: .cancel) { model.pendingRemoval = nil }
            } message: { service in
                Text(
                    "Jerd stops \(service.name) and removes its registration. Its database files stay in the data folder, and Retained Databases can restore it."
                )
            }
            .confirmationDialog(
                model.pendingRuntimeInstall.map(DatabaseRuntimeCopy.confirmationTitle) ?? "",
                isPresented: isConfirmingInstall, titleVisibility: .visible, presenting: model.pendingRuntimeInstall
            ) { _ in
                Button(model.pendingRuntimeInstall.map(DatabaseRuntimeCopy.confirmTitle) ?? "Install") {
                    model.confirmRuntimeInstall()
                }
                .disabled(isQuitting)
                Button("Cancel", role: .cancel) { model.pendingRuntimeInstall = nil }
            } message: { offer in
                Text(DatabaseRuntimeCopy.confirmationMessage(offer))
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

    private var isConfirmingInstall: Binding<Bool> {
        Binding {
            model.pendingRuntimeInstall != nil
        } set: { isPresented in
            if !isPresented { model.pendingRuntimeInstall = nil }
        }
    }

    private var isConfirmingRemoval: Binding<Bool> {
        Binding {
            model.pendingRemoval != nil
        } set: { isPresented in
            if !isPresented { model.pendingRemoval = nil }
        }
    }
}

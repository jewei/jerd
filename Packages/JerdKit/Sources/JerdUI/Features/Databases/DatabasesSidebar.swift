import JerdDatabases
import JerdDesign
import SwiftUI

/// The Databases sidebar: every service with its engine, port, and status.
struct DatabasesSidebar: View {
    @Bindable var state: AppState
    let model: DatabasesModel

    var body: some View {
        List(selection: selection) {
            Section("Services") {
                ForEach(model.services) { service in
                    SidebarRow(
                        service.name, subtitle: subtitle(for: service),
                        status: model.displayStatus(of: service.id)
                    )
                    .tag(SidebarSelection.database(service.id))
                    .accessibilityIdentifier(AccessibilityIdentifier.make("sidebar", "database", service.name))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DatabasesSidebarFooter(model: model)
        }
    }

    private func subtitle(for service: DatabaseService) -> String {
        guard let runtime = model.runtime(of: service) else { return "Runtime unavailable" }
        return "\(runtime.engine.title) \(runtime.version) · \(service.port)"
    }

    private var selection: Binding<SidebarSelection?> {
        Binding {
            state.navigation.selection(in: .databases)
        } set: { selection in
            state.navigation.select(selection)
        }
    }
}

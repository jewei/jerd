import JerdDatabases
import JerdDesign
import SwiftUI

/// The Databases sidebar: every service with its engine, port, and status.
struct DatabasesSidebar: View {
    let state: AppState
    let model: DatabasesModel

    var body: some View {
        List(selection: state.sidebarSelection(in: .databases)) {
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
        .sidebarFooter {
            DatabasesSidebarFooter(model: model)
        }
    }

    private func subtitle(for service: DatabaseService) -> String {
        guard let runtime = model.runtime(of: service) else { return "Runtime unavailable" }
        return "\(runtime.engine.title) \(runtime.version) · \(service.port)"
    }
}

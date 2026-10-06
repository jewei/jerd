import JerdDatabases
import JerdDesign
import SwiftUI

/// The footer of the Databases sidebar: the Add menu by engine, Retained Databases…, the
/// count, and ⌘N for the first engine.
struct DatabasesSidebarFooter: View {
    let model: DatabasesModel

    var body: some View {
        SidebarFooter(addTitle: "Add Database", caption: caption) {
            ForEach(DatabaseEngine.allCases, id: \.self) { engine in
                Button("Add \(engine.title)…") { model.beginAdd(engine) }
                    .disabled(!model.canAdd || !model.availableEngines.contains(engine))
            }
            Divider()
            Button("Retained Databases…") { model.showRetained() }
                .disabled(!model.loadState.isLoaded || model.isShuttingDown)
        }
        .addShortcut("Add Database", isEnabled: model.canAdd) {
            if let engine = model.availableEngines.first { model.beginAdd(engine) }
        }
    }

    private var caption: String {
        let running = model.services.filter { model.state(of: $0.id).isRunning }.count
        let count = model.services.count == 1 ? "1 service" : "\(model.services.count) services"
        return running > 0 ? "\(count) · \(running) running" : count
    }
}

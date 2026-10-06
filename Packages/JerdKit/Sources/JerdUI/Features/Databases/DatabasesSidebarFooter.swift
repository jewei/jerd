import JerdDatabases
import JerdDesign
import SwiftUI

/// The footer of the Databases sidebar: the Add menu by engine, Retained Databases…, and the
/// count. File › New Database… (⌘N) is the section's `newItemAction`.
struct DatabasesSidebarFooter: View {
    let model: DatabasesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        SidebarFooter(addTitle: "Add Database", caption: caption) {
            ForEach(DatabaseEngine.allCases, id: \.self) { engine in
                Button("Add \(engine.title)…") { model.beginAdd(engine) }
                    .disabled(isQuitting || !model.canAdd || !model.availableEngines.contains(engine))
            }
            Divider()
            Button("Retained Databases…") { model.showRetained() }
                .disabled(isQuitting || !model.canShowRetained)
        }
    }

    private var caption: String {
        let running = model.services.filter { model.state(of: $0.id).isRunning }.count
        let count = model.services.count == 1 ? "1 service" : "\(model.services.count) services"
        return running > 0 ? "\(count) · \(running) running" : count
    }
}

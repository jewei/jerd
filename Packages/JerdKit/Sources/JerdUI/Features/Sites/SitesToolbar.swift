import JerdDesign
import SwiftUI

/// The Sites toolbar (spec F 3.2.2): progress, Runtimes, and the System Setup menu. Retry Load
/// is on the page, not here, so the toolbar fits the compact window in every state.
struct SitesToolbar: View {
    let model: SitesModel

    var body: some View {
        if model.operation.isWorking {
            BusyIndicator(model.operation.workingMessage ?? "Working")
        }
        Button("Runtimes", systemImage: "shippingbox") { model.shell.show(.dashboard(.runtimes)) }
            .help("Manage runtimes")
            .accessibilityIdentifier("sites.toolbar.runtimes")
        SystemSetupMenu(model: model)
    }
}

import JerdDesign
import SwiftUI

/// The Sites toolbar (spec F 3.2.2): progress, Retry Load after a failed load, Runtimes, and
/// the System Setup menu.
struct SitesToolbar: View {
    let model: SitesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        if model.operation.isWorking {
            BusyIndicator(model.operation.workingMessage ?? "Working")
        }
        if !model.isLoaded {
            Button("Retry Load", systemImage: "arrow.clockwise") { model.retryLoad() }
                .help("Retry loading sites")
                .disabled(model.isBusy || isQuitting)
                .accessibilityIdentifier("sites.toolbar.retry-load")
        }
        Button("Runtimes", systemImage: "shippingbox") { model.shell.show(.dashboard(.runtimes)) }
            .help("Manage runtimes")
            .accessibilityIdentifier("sites.toolbar.runtimes")
        SystemSetupMenu(model: model)
    }
}

import JerdDesign
import SwiftUI

/// The RustFS version and the two ports, with Edit Ports… while storage is stopped.
struct StorageServiceSection: View {
    let model: StorageModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        Section {
            ValueRow("RustFS", value: model.settings.runtime.map { "Version \($0.version)" } ?? "Not installed")
            ActionRow("Ports", detail: "S3 \(model.settings.apiPort) · Console \(model.settings.consolePort)") {
                Button("Edit Ports…", action: model.editPorts)
                    .disabled(isQuitting || !model.canEditPorts)
                    .accessibilityLabel("Edit storage ports")
                    .accessibilityIdentifier("storage.edit-ports")
            }
        } header: {
            Text("Service")
        } footer: {
            FormFooter(
                model.state.offersStop
                    ? "Stop storage to change its ports. Port changes keep all buckets and objects."
                    : "Both ports are limited to this Mac. Port changes keep all buckets and objects.")
        }
    }
}

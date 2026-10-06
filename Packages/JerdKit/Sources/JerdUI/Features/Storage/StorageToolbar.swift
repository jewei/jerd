import JerdDesign
import SwiftUI

/// The toolbar items of the Storage section: Refresh Buckets and the storage ports.
struct StorageToolbar: View {
    let model: StorageModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        ToolbarActionButtons(actions: Self.actions(for: model, isQuitting: isQuitting))
    }

    /// Both start work, so both are off during a quit. The ports can change only while storage
    /// is stopped; the tooltip says so.
    static func actions(for model: StorageModel, isQuitting: Bool) -> [PageAction] {
        [
            PageAction(
                "Refresh Buckets", systemImage: "arrow.clockwise",
                isEnabled: model.canChange && model.state.isRunning && !isQuitting,
                help: model.state.isRunning ? "List the buckets again" : "Start storage to list its buckets.",
                identifier: "storage.toolbar.refresh"
            ) { model.refreshBuckets() },
            PageAction(
                "Storage Settings", systemImage: "gearshape", isEnabled: model.canEditPorts && !isQuitting,
                help: model.state.offersStop ? "Stop storage to change its ports." : "Edit the storage ports",
                identifier: "storage.toolbar.settings"
            ) { model.editPorts() },
        ]
    }
}

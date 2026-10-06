import JerdDesign
import SwiftUI

/// The toolbar items of the Databases section (spec F 3.3): Retained Databases…, which also
/// works with the sidebar hidden, and the database runtimes.
struct DatabasesToolbar: View {
    let model: DatabasesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        ToolbarActionButtons(actions: Self.actions(for: model, isQuitting: isQuitting))
    }

    /// Retained Databases… inspects data folders, so it is off during a quit. Runtimes only
    /// shows another page.
    static func actions(for model: DatabasesModel, isQuitting: Bool) -> [PageAction] {
        [
            PageAction(
                "Retained Databases…", systemImage: "arrow.uturn.backward.circle",
                isEnabled: model.canShowRetained && !isQuitting,
                help: "Restore a removed database registration", identifier: "databases.toolbar.retained"
            ) { model.showRetained() },
            PageAction(
                "Database Runtimes", systemImage: "shippingbox", help: "Show the database runtimes in Runtimes",
                identifier: "databases.toolbar.runtimes"
            ) { model.showRuntimes() },
        ]
    }
}

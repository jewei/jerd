import SwiftUI

/// The trailing toolbar items of the current section, for example Runtimes and the System
/// Setup menu in Sites. Only the current section shows its items, because every page stays
/// alive behind the visible one. A feature package replaces the `EmptyView()` line of its
/// section with its toolbar view; nothing else in the shell changes. See the JerdUI README.
struct SectionToolbar: View {
    let state: AppState

    var body: some View {
        switch state.navigation.section {
        case .dashboard:
            EmptyView()
        case .sites:
            EmptyView()
        case .databases:
            DatabasesToolbar(model: state.databases)
        case .storage:
            StorageToolbar(model: state.storage)
        case .mail:
            EmptyView()
        }
    }
}

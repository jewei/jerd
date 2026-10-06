import JerdDesign
import SwiftUI

/// The sidebar column of the current section. Mail has none.
struct WorkspaceSidebar: View {
    let state: AppState

    var body: some View {
        content
            // The workspace has its own `SidebarToggle`, which is off on Mail. The system
            // toggle goes only when it is removed on the sidebar column, not on the split view.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(
                min: WindowMetrics.sidebarMinimumWidth, ideal: WindowMetrics.sidebarIdealWidth,
                max: WindowMetrics.sidebarMaximumWidth)
    }

    /// The feature work packages replace each empty list with their sidebar.
    @ViewBuilder private var content: some View {
        switch state.navigation.section {
        case .dashboard:
            DashboardSidebar(state: state)
        case .sites, .mail:
            List {}
                .listStyle(.sidebar)
        case .databases:
            DatabasesSidebar(state: state, model: state.databases)
        case .storage:
            StorageSidebar(state: state, model: state.storage)
        }
    }
}

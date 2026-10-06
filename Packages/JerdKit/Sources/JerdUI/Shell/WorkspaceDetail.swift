import JerdDesign
import SwiftUI

/// The detail column: one retained page per section, created once. Only the page of the
/// current section is visible.
struct WorkspaceDetail: View {
    let state: AppState

    var body: some View {
        ZStack {
            ForEach(AppSection.allCases) { section in
                page(for: section)
                    .retainedPage(isVisible: state.navigation.section == section)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The feature work packages replace each placeholder with their page.
    @ViewBuilder
    private func page(for section: AppSection) -> some View {
        switch section {
        case .dashboard:
            DashboardPages(state: state)
        case .sites, .databases, .storage, .mail:
            PlaceholderPage(section: section)
        }
    }
}

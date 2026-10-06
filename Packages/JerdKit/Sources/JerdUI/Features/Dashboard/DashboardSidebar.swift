import JerdDesign
import SwiftUI

/// The five pages of the Dashboard section, in their fixed order.
struct DashboardSidebar: View {
    @Bindable var state: AppState

    var body: some View {
        List(selection: selection) {
            ForEach(DashboardPage.allCases) { page in
                DashboardSidebarRow(page: page, isSelected: state.navigation.dashboardPage == page)
                    .tag(page)
                    .accessibilityIdentifier(AccessibilityIdentifier.make("sidebar", "dashboard", page.title))
            }
        }
        .listStyle(.sidebar)
    }

    /// A native list refresh can report no selection; that never clears the page.
    private var selection: Binding<DashboardPage?> {
        Binding {
            state.navigation.dashboardPage
        } set: { page in
            if let page { state.navigation.dashboardPage = page }
        }
    }
}

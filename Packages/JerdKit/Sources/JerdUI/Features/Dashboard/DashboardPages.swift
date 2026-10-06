import SwiftUI

/// The detail of the Dashboard section: the selected dashboard page.
struct DashboardPages: View {
    let state: AppState

    var body: some View {
        switch state.navigation.dashboardPage {
        case .overview:
            OverviewPage(state: state)
        case .appearance:
            AppearancePage(model: state.appearance)
        case .runtimes:
            RuntimesPage(model: state.runtimes)
        case .advanced:
            AdvancedPage(model: state.advanced)
        case .about:
            AboutPage(updates: state.appUpdates, appearance: state.appearance, info: state.info) {
                state.navigation.show(.dashboard(.runtimes))
            }
        }
    }
}

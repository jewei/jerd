import JerdDesign
import SwiftUI

/// Dashboard › Dashboard: one card per service area and the runtimes row. Errors stay on the
/// page that owns them; a card shows a failure only as its status.
struct OverviewPage: View {
    let state: AppState
    private let columns = [GridItem(.adaptive(minimum: 280), spacing: Spacing.large, alignment: .top)]

    var body: some View {
        PageScaffold {
            PageHeader("Dashboard", subtitle: "Your local development environment")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.large) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.large) {
                    ForEach(DashboardCards.sections, id: \.self) { section in
                        FeatureCard(section: section, summary: DashboardCards.summary(for: section, in: state)) {
                            state.navigation.show(.section(section))
                        }
                    }
                }
                RuntimesSummaryRow(defaultPHP: state.runtimes.inventory.defaultPHP) {
                    state.navigation.show(.dashboard(.runtimes))
                }
            }
        }
    }
}

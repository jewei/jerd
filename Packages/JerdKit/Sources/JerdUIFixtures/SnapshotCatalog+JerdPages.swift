import JerdDesign
import JerdSnapshotSupport
import JerdUI

extension SnapshotCatalog {
    /// A tall window for long pages, so every section can be reviewed in one image.
    package static let fullPage = SnapshotSize(name: "full", width: WindowMetrics.standardSize.width, height: 2600)

    /// Registers one entry per fixture scenario: the full window, at both window sizes, in
    /// light and dark. Long pages add the tall size, and an `-end` entry scrolled to their end
    /// at both window sizes.
    package mutating func addJerdPages() {
        for scenario in FixtureScenario.allCases {
            let sizes = SnapshotSize.windowSizes + (scenario.showsFullPage ? [Self.fullPage] : [])
            addPage(scenario, name: scenario.rawValue, sizes: sizes, scroll: .top)
            if scenario.showsFullPage {
                addPage(scenario, name: "\(scenario.rawValue)-end", sizes: SnapshotSize.windowSizes, scroll: .end)
            }
        }
        addSitesSheets()
    }

    /// One window entry of a scenario, with its own fixture.
    private mutating func addPage(
        _ scenario: FixtureScenario, name: String, sizes: [SnapshotSize], scroll: SnapshotScrollPosition
    ) {
        let host = ScenarioHost(scenario)
        add(
            name, sizes: sizes, appearances: scenario.snapshotAppearances, scroll: scroll, isReady: { host.isReady },
            view: {
                JerdWorkspace(state: host.fixture.state)
                    .task { await host.prepare() }
            })
    }
}

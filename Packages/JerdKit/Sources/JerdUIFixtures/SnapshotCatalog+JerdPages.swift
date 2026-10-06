import JerdDesign
import JerdSnapshotSupport
import JerdUI

extension SnapshotCatalog {
    /// A tall window for long pages, so every section can be reviewed in one image.
    package static let fullPage = SnapshotSize(name: "full", width: WindowMetrics.standardSize.width, height: 2600)

    /// Registers one entry per fixture scenario: the full window, at both window sizes, in
    /// light and dark. Long pages add the tall size.
    package mutating func addJerdPages() {
        for scenario in FixtureScenario.allCases {
            let host = ScenarioHost(scenario)
            let sizes = SnapshotSize.windowSizes + (scenario.showsFullPage ? [Self.fullPage] : [])
            add(
                scenario.rawValue, sizes: sizes, isReady: { host.isReady },
                view: {
                    JerdWorkspace(state: host.fixture.state)
                        .task { await host.prepare() }
                })
        }
        addSitesSheets()
    }
}

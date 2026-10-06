import JerdDesign
import JerdSnapshotSupport
import JerdUI
import SwiftUI

extension SnapshotCatalog {
    /// Registers each Sites and tunnel sheet alone, at the sheet width. A long sheet adds an
    /// `-end` entry scrolled to its end.
    package mutating func addSitesSheets() {
        for scenario in SitesSheetScenario.allCases {
            addSitesSheet(scenario, name: scenario.rawValue, scroll: .top)
            if scenario.showsEnd {
                addSitesSheet(scenario, name: "\(scenario.rawValue)-end", scroll: .end)
            }
        }
    }

    /// One sheet entry of a scenario, with its own fixture.
    private mutating func addSitesSheet(_ scenario: SitesSheetScenario, name: String, scroll: SnapshotScrollPosition) {
        let host = SitesSheetHost(scenario)
        add(
            name, sizes: [.fittingHeight(name: "sheet", width: SheetSize.wide.width)],
            appearances: SnapshotAppearance.allCases, chrome: .content, scroll: scroll, isReady: { host.isReady },
            view: {
                SitesSheetContent(model: host.fixture.state.sites)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .task { await host.prepare() }
            })
    }
}

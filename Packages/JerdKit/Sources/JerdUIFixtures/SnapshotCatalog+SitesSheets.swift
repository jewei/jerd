import JerdDesign
import JerdSnapshotSupport
import JerdUI
import SwiftUI

extension SnapshotCatalog {
    /// Registers each Sites and tunnel sheet alone, at the sheet width, in light and dark.
    package mutating func addSitesSheets() {
        for scenario in SitesSheetScenario.allCases {
            let host = SitesSheetHost(scenario)
            add(
                scenario.rawValue, sizes: [.fittingHeight(name: "sheet", width: SheetSize.wide.width)],
                chrome: .content, isReady: { host.isReady },
                view: {
                    SitesSheetContent(model: host.fixture.state.sites)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .task { await host.prepare() }
                })
        }
    }
}

import JerdDesign
import JerdSnapshotSupport
import JerdUI
import SwiftUI

extension SnapshotCatalog {
    /// Registers every Databases, Storage, and Mail scenario: windows at both sizes, sheets alone
    /// at their own width and height. Long pages add an `-end` entry scrolled to their end.
    package mutating func addServicePages() {
        for scenario in ServiceScenario.allCases {
            switch scenario.kind {
            case .window:
                let sizes = SnapshotSize.windowSizes + (scenario == .advancedCommandLineTools ? [Self.fullPage] : [])
                addServiceWindow(scenario, name: scenario.rawValue, sizes: sizes, scroll: .top)
                if scenario.showsEnd {
                    addServiceWindow(
                        scenario, name: "\(scenario.rawValue)-end", sizes: SnapshotSize.windowSizes, scroll: .end)
                }
            case .sheet:
                let host = ServiceScenarioHost(scenario)
                add(
                    scenario.rawValue, sizes: [Self.sheetSize(for: scenario)],
                    appearances: scenario.snapshotAppearances, chrome: .content, isReady: { host.isReady },
                    view: {
                        ServiceSheetView(scenario: scenario, state: host.fixture.state)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .task { await host.prepare() }
                    })
            }
        }
    }

    /// One window entry of a scenario, with its own fixture.
    private mutating func addServiceWindow(
        _ scenario: ServiceScenario, name: String, sizes: [SnapshotSize], scroll: SnapshotScrollPosition
    ) {
        let host = ServiceScenarioHost(scenario)
        add(
            name, sizes: sizes, appearances: scenario.snapshotAppearances, scroll: scroll, isReady: { host.isReady },
            view: {
                JerdWorkspace(state: host.fixture.state)
                    .task { await host.prepare() }
            })
    }

    private static func sheetSize(for scenario: ServiceScenario) -> SnapshotSize {
        let width = scenario == .retainedDatabases ? SheetSize.wide.width : SheetSize.standard.width
        return .fittingHeight(name: "sheet", width: width)
    }
}

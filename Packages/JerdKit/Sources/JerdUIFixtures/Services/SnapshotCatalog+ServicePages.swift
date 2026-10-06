import JerdDesign
import JerdSnapshotSupport
import JerdUI
import SwiftUI

extension SnapshotCatalog {
    /// Registers every Databases, Storage, and Mail scenario: windows at both sizes, sheets alone
    /// at their own width and height.
    package mutating func addServicePages() {
        for scenario in ServiceScenario.allCases {
            let host = ServiceScenarioHost(scenario)
            switch scenario.kind {
            case .window:
                let sizes = SnapshotSize.windowSizes + (scenario == .advancedCommandLineTools ? [Self.fullPage] : [])
                add(
                    scenario.rawValue, sizes: sizes, isReady: { host.isReady },
                    view: {
                        JerdWorkspace(state: host.fixture.state)
                            .task { await host.prepare() }
                    })
            case .sheet:
                add(
                    scenario.rawValue, sizes: [Self.sheetSize(for: scenario)], chrome: .content,
                    isReady: { host.isReady },
                    view: {
                        ServiceSheetView(scenario: scenario, state: host.fixture.state)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .task { await host.prepare() }
                    })
            }
        }
    }

    private static func sheetSize(for scenario: ServiceScenario) -> SnapshotSize {
        let width = scenario == .retainedDatabases ? SheetSize.wide.width : SheetSize.standard.width
        return .fittingHeight(name: "sheet", width: width)
    }
}

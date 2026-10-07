import JerdDesign
import JerdUIFixtures
import SwiftUI
import Testing

@testable import JerdSnapshotSupport
@testable import JerdUI

@Suite("Service page snapshots", .serialized)
@MainActor
struct ServiceSnapshotTests {
    @Test("Every service scenario is registered once")
    func everyScenarioRegistered() {
        var catalog = SnapshotCatalog()
        catalog.addServicePages()
        let names = ServiceScenario.allCases.flatMap { scenario in
            [scenario.rawValue] + (scenario.showsEnd ? ["\(scenario.rawValue)-end"] : [])
        }
        #expect(catalog.entries.map(\.name) == names)
        #expect(catalog.duplicateNames.isEmpty)
    }

    /// In its own process; see `SnapshotProcess`.
    @Test("Every service scenario renders and shows what it promises, in a separate process")
    func everyScenarioRenders() async throws {
        let result = try await SnapshotProcess.run(["--check"] + ServiceScenario.allCases.map(\.rawValue))
        #expect(result.status == 0, "jerd-snapshots --check failed: \(result.errors)")
        #expect(result.output.contains("Checked "))
    }
}

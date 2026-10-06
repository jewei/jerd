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

    @Test("Every service scenario renders and shows what it promises", arguments: ServiceScenario.allCases)
    func rendersScenario(scenario: ServiceScenario) async throws {
        var catalog = SnapshotCatalog()
        catalog.addServicePages()
        let entry = try #require(catalog.entries.first { $0.name == scenario.rawValue })
        let size = try #require(entry.sizes.first { $0 != .standard })
        let image = try await SnapshotRenderer().render(
            entry.makeView(), size: size, appearance: .light, chrome: entry.chrome, name: entry.name,
            isReady: entry.isReady)
        #expect(image.pixelsWide > 0)
        #expect(entry.isReady())
    }
}

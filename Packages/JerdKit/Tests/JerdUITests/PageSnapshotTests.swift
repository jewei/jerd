import JerdDesign
import JerdUIFixtures
import SwiftUI
import Testing

@testable import JerdSnapshotSupport
@testable import JerdUI

@Suite("Page snapshots", .serialized)
@MainActor
struct PageSnapshotTests {
    @Test("Every fixture scenario is registered once, with both window sizes")
    func everyScenarioRegistered() {
        var catalog = SnapshotCatalog()
        catalog.addJerdPages()
        #expect(catalog.entries.map(\.name) == FixtureScenario.allCases.map(\.rawValue))
        #expect(catalog.duplicateNames.isEmpty)
        #expect(catalog.entries.allSatisfy { Set(SnapshotSize.windowSizes).isSubset(of: $0.sizes) })
    }

    @Test("Every registered page renders at the compact window size", arguments: FixtureScenario.allCases)
    func rendersPage(scenario: FixtureScenario) async throws {
        var catalog = SnapshotCatalog()
        catalog.addJerdPages()
        let entry = try #require(catalog.entries.first { $0.name == scenario.rawValue })
        let image = try await SnapshotRenderer().render(
            entry.makeView(), size: .compact, appearance: .light, chrome: entry.chrome, name: entry.name,
            isReady: entry.isReady)
        #expect(image.pixelsWide == 1640)
        #expect(entry.isReady())
    }

    @Test("Hidden retained pages announce nothing; the visible page speaks")
    func retainedPagesAreSilent() async {
        var spoken: [String] = []
        let announcer = MessageAnnouncer { spoken.append($0) }
        let view = ZStack {
            InlineMessage("Hidden error", kind: .error).retainedPage(isVisible: false)
            InlineMessage("Visible error", kind: .error).retainedPage(isVisible: true)
        }
        .environment(\.messageAnnouncer, announcer)
        let image = try? await SnapshotRenderer().render(
            view, size: SnapshotSize(name: "test", width: 300, height: 100), appearance: .light, chrome: .content)
        #expect(image != nil)
        #expect(spoken == ["Error: Visible error"])
    }
}

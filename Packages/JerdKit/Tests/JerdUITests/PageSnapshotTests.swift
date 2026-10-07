import Foundation
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
        let pageNames = FixtureScenario.allCases.flatMap { scenario in
            [scenario.rawValue] + (scenario.showsFullPage ? ["\(scenario.rawValue)-end"] : [])
        }
        let sheetNames = SitesSheetScenario.allCases.flatMap { scenario in
            [scenario.rawValue] + (scenario.showsEnd ? ["\(scenario.rawValue)-end"] : [])
        }
        #expect(catalog.entries.map(\.name) == pageNames + sheetNames)
        #expect(catalog.duplicateNames.isEmpty)
        let pages = catalog.entries.filter { entry in FixtureScenario.allCases.contains { $0.rawValue == entry.name } }
        #expect(pages.allSatisfy { Set(SnapshotSize.windowSizes).isSubset(of: $0.sizes) })
    }

    /// Renders every page and Sites sheet once in the built `jerd-snapshots`, in its own
    /// process. In this process the renderings held the main actor for over a minute in slices
    /// of about 0.25 s, so other main-actor suites ran up to 30 s and could pass their limits.
    @Test("Every registered page and Sites sheet renders, in a separate process")
    func everyPageAndSheetRenders() async throws {
        let names = FixtureScenario.allCases.map(\.rawValue) + SitesSheetScenario.allCases.map(\.rawValue)
        let result = try await SnapshotProcess.run(["--check"] + names)
        #expect(result.status == 0, "jerd-snapshots --check failed: \(result.errors)")
        #expect(result.output.contains("Checked "))
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

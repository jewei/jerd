import JerdDesign
import JerdUIFixtures
import Testing

@testable import JerdSnapshotSupport
@testable import JerdUI

/// Which states the snapshot catalog shows: the end of long pages and sheets, and every page and
/// sheet in light, dark, and both Increase Contrast variants.
@Suite("Snapshot coverage")
@MainActor
struct SnapshotCoverageTests {
    private var catalog: SnapshotCatalog {
        var catalog = SnapshotCatalog()
        catalog.addJerdPages()
        catalog.addServicePages()
        return catalog
    }

    @Test("The HTTPS approval, the site editor, and the tunnel editor also render at their end")
    func longSheetsRenderTheirEnd() throws {
        for name in ["sheet-https-approval-end", "sheet-site-editor-add-end", "sheet-tunnel-editor-add-end"] {
            let entry = try #require(catalog.entries.first { $0.name == name }, "\(name) is missing")
            #expect(entry.scroll == .end)
            #expect(entry.chrome == .content)
        }
    }

    @Test("Each long page renders at its end at both window sizes")
    func longPagesRenderTheirEnd() throws {
        let long =
            FixtureScenario.allCases.filter(\.showsFullPage).map(\.rawValue)
            + ServiceScenario.allCases.filter(\.showsEnd).map(\.rawValue)
        #expect(long.count >= 10)
        for name in long {
            let entry = try #require(catalog.entries.first { $0.name == "\(name)-end" }, "\(name)-end is missing")
            #expect(entry.scroll == .end)
            #expect(entry.sizes == SnapshotSize.windowSizes)
        }
        #expect(catalog.entries.filter { !$0.name.hasSuffix("-end") }.allSatisfy { $0.scroll == .top })
    }

    @Test("Every sheet renders in light, dark, and both Increase Contrast variants")
    func everySheetHasContrast() {
        let sheets = catalog.entries.filter { $0.chrome == .content }
        #expect(sheets.count == SitesSheetScenario.allCases.count + 3 + 8)
        for sheet in sheets {
            #expect(Set(sheet.appearances) == Set(SnapshotAppearance.allCases), "\(sheet.name) lacks an appearance")
        }
    }

    @Test("Every page renders in dark, and at least one state of it with Increase Contrast")
    func everyPageHasContrast() {
        var pages: [String: [SnapshotAppearance]] = [:]
        for scenario in FixtureScenario.allCases {
            pages[Self.page(scenario.destination), default: []] += scenario.snapshotAppearances
        }
        for scenario in ServiceScenario.allCases where scenario.kind == .window {
            pages[Self.page(scenario.destination), default: []] += scenario.snapshotAppearances
        }
        #expect(pages.count >= 13)
        for (page, appearances) in pages {
            #expect(Set(appearances) == Set(SnapshotAppearance.allCases), "\(page) lacks an appearance")
        }
    }

    /// The page that a destination shows, without the identity of the selected item.
    private static func page(_ destination: Destination) -> String {
        switch destination {
        case .section(let section): "section \(section.title)"
        case .dashboard(let page): "dashboard \(page)"
        case .item(.site): "site"
        case .item(.tunnel): "tunnel"
        case .item(.database): "database"
        case .item(.bucket): "bucket"
        }
    }
}

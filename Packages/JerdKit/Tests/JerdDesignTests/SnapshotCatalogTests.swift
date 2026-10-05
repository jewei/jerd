import SwiftUI
import Testing

@testable import JerdDesign

@Suite("Snapshot catalog")
@MainActor
struct SnapshotCatalogTests {
    private func catalog(_ names: [String]) -> SnapshotCatalog {
        var catalog = SnapshotCatalog()
        for name in names {
            catalog.add(name) { Text(name) }
        }
        return catalog
    }

    @Test("A page registered with one line uses both window sizes, light and dark, and the window frame")
    func defaultsForPages() throws {
        let entry = try #require(catalog(["sites"]).entries.first)
        #expect(entry.sizes == [.standard, .compact])
        #expect(entry.appearances == [.light, .dark])
        #expect(entry.chrome == .window(title: "Jerd"))
    }

    @Test("File names are name, appearance, then size")
    func fileNames() throws {
        let entry = try #require(catalog(["sites-running"]).entries.first)
        #expect(entry.fileName(appearance: .light, size: .standard) == "sites-running-light-standard.png")
        #expect(entry.fileName(appearance: .dark, size: .compact) == "sites-running-dark-compact.png")
        #expect(entry.fileName(appearance: .darkContrast, size: .compact) == "sites-running-dark-contrast-compact.png")
    }

    @Test("A filter selects the exact name and names that continue it after a hyphen")
    func filterMatching() {
        let catalog = catalog(["gallery-status", "gallery-rows", "gallerystatus", "sites"])
        #expect(catalog.entries(matching: ["gallery"]).map(\.name) == ["gallery-status", "gallery-rows"])
        #expect(catalog.entries(matching: ["sites", "gallery-rows"]).map(\.name) == ["gallery-rows", "sites"])
        #expect(catalog.entries(matching: []).count == 4)
    }

    @Test("Filters that match nothing are reported")
    func unmatchedFilters() {
        #expect(catalog(["sites"]).unmatchedFilters(["sites", "mail"]) == ["mail"])
    }

    @Test("Duplicate names are reported once each, so files are never overwritten")
    func duplicateNames() {
        #expect(catalog(["a", "b", "a", "a"]).duplicateNames == ["a"])
        #expect(catalog(["a", "b"]).duplicateNames.isEmpty)
    }

    @Test("The component gallery registers every gallery page with unique names")
    func galleryRegistration() {
        var catalog = SnapshotCatalog()
        catalog.addComponentGallery()
        #expect(catalog.entries.map(\.name) == GalleryPage.allCases.map(\.snapshotName))
        #expect(catalog.duplicateNames.isEmpty)
    }

    @Test("Window gallery pages render at both window sizes")
    func windowPagesUseWindowSizes() {
        for page in GalleryPage.allCases where page.usesWindow {
            #expect(page.sizes == SnapshotSize.windowSizes)
        }
    }
}

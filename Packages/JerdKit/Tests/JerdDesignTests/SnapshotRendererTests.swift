import AppKit
import SwiftUI
import Testing

@testable import JerdDesign

@Suite("Snapshot renderer")
@MainActor
struct SnapshotRendererTests {
    @Test("Renders a content snapshot at scale 2 with the exact pixel size")
    func rendersContentAtExactSize() throws {
        let size = SnapshotSize(name: "test", width: 120, height: 80)
        let image = try SnapshotRenderer().render(Color.red, size: size, appearance: .light, chrome: .content)
        #expect(image.pixelsWide == 240)
        #expect(image.pixelsHigh == 160)
        #expect(ImageProbe(image).distinctColorCount() == 1)
    }

    @Test("Renders the full window frame, including the titlebar, at the window size")
    func rendersWindowFrame() throws {
        let image = try SnapshotRenderer().render(
            Text("Window"), size: .compact, appearance: .dark, chrome: .window(title: "Jerd"))
        #expect(image.pixelsWide == 1640)
        #expect(image.pixelsHigh == 1080)
    }

    @Test("Light and dark appearances produce different pixels")
    func appearancesDiffer() throws {
        let size = SnapshotSize(name: "test", width: 200, height: 120)
        let view = FormPage {
            PageHeader("Title")
        } content: {
            Text("Row")
        }
        let light = try SnapshotRenderer().render(view, size: size, appearance: .light, chrome: .content)
        let dark = try SnapshotRenderer().render(view, size: size, appearance: .dark, chrome: .content)
        #expect(ImageProbe(light).averageBrightness() > ImageProbe(dark).averageBrightness())
    }

    @Test("PNG data starts with the PNG signature")
    func encodesPNG() throws {
        let size = SnapshotSize(name: "test", width: 20, height: 20)
        let data = try SnapshotRenderer().renderPNG(Color.blue, size: size, appearance: .light, chrome: .content)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test(
        "Every gallery page renders a non-empty image of its size in every appearance", arguments: GalleryPage.allCases)
    func galleryRenders(page: GalleryPage) throws {
        var catalog = SnapshotCatalog()
        catalog.addComponentGallery()
        let entry = try #require(catalog.entries.first { $0.name == page.snapshotName })
        let renderer = SnapshotRenderer()
        for size in entry.sizes {
            for appearance in entry.appearances {
                let image = try renderer.render(
                    entry.makeView(), size: size, appearance: appearance, chrome: entry.chrome)
                #expect(image.pixelsWide == Int(size.width * SnapshotRenderer.scale))
                #expect(image.pixelsHigh == Int(size.height * SnapshotRenderer.scale))
                #expect(ImageProbe(image).distinctColorCount() > 50, "\(page) \(appearance) is blank")
            }
        }
    }
}

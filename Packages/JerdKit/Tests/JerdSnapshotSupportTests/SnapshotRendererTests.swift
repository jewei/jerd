import AppKit
import JerdDesign
import SwiftUI
import Testing

@testable import JerdSnapshotSupport

@Suite("Snapshot renderer")
@MainActor
struct SnapshotRendererTests {
    @Test("Renders a content snapshot at scale 2 with the exact pixel size")
    func rendersContentAtExactSize() async throws {
        let size = SnapshotSize(name: "test", width: 120, height: 80)
        let image = try await SnapshotRenderer().render(Color.red, size: size, appearance: .light, chrome: .content)
        #expect(image.pixelsWide == 240)
        #expect(image.pixelsHigh == 160)
        #expect(ImageProbe(image).distinctColorCount() == 1)
    }

    @Test("Renders the full window frame, including the titlebar, at the window size")
    func rendersWindowFrame() async throws {
        let image = try await SnapshotRenderer().render(
            Text("Window"), size: .compact, appearance: .dark, chrome: .window(title: "Jerd"))
        #expect(image.pixelsWide == 1640)
        #expect(image.pixelsHigh == 1080)
    }

    @Test("A fitting height takes the ideal height of the view")
    func fittingHeight() async throws {
        let size = SnapshotSize.fittingHeight(name: "fit", width: 100)
        let image = try await SnapshotRenderer().render(
            Color.blue.frame(height: 77), size: size, appearance: .light, chrome: .content)
        #expect(image.pixelsWide == 200)
        #expect(image.pixelsHigh == 154)
    }

    @Test("Light and dark appearances produce different pixels")
    func appearancesDiffer() async throws {
        let size = SnapshotSize(name: "test", width: 200, height: 120)
        let view = FormPage {
            PageHeader("Title")
        } content: {
            Text("Row")
        }
        let light = try await SnapshotRenderer().render(view, size: size, appearance: .light, chrome: .content)
        let dark = try await SnapshotRenderer().render(view, size: size, appearance: .dark, chrome: .content)
        #expect(ImageProbe(light).averageBrightness() > ImageProbe(dark).averageBrightness())
    }

    @Test("Two renderings of one window entry have the same bytes")
    func renderingIsDeterministic() async throws {
        var catalog = SnapshotCatalog()
        catalog.addComponentGallery()
        let entry = try #require(catalog.entries.first { $0.name == GalleryPage.workspace.snapshotName })
        let renderer = SnapshotRenderer()
        let first = try await renderer.renderPNG(
            entry.makeView(), size: .compact, appearance: .light, chrome: entry.chrome)
        let second = try await renderer.renderPNG(
            entry.makeView(), size: .compact, appearance: .light, chrome: entry.chrome)
        #expect(first == second)
    }

    @Test(
        "An Increase Contrast rendering is refused in a process without Increase Contrast",
        arguments: [SnapshotAppearance.lightContrast, .darkContrast])
    func contrastNeedsTheProcessSetting(appearance: SnapshotAppearance) async {
        let size = SnapshotSize(name: "test", width: 20, height: 20)
        await #expect(
            throws: SnapshotError.appearanceUnavailable(
                "x.png", expected: appearance.resolvedAppearanceName.rawValue,
                actual: appearance.colorScheme == .light ? "NSAppearanceNameAqua" : "NSAppearanceNameDarkAqua")
        ) {
            _ = try await SnapshotRenderer().render(
                Color.red, size: size, appearance: appearance, chrome: .content, name: "x.png")
        }
    }

    @Test("The renderer waits until asynchronous content is ready")
    func waitsForReadiness() async throws {
        let model = LoadingModel()
        let size = SnapshotSize(name: "test", width: 40, height: 40)
        let image = try await SnapshotRenderer().render(
            LoadingView(model: model), size: size, appearance: .light, chrome: .content, isReady: { model.isLoaded })
        #expect(model.isLoaded)
        let blue = try await blueImage(size)
        #expect(ImageProbe(image).components(x: 40, y: 40) == ImageProbe(blue).components(x: 40, y: 40))
    }

    @Test("A view that is never ready fails with the file name, after the pass limit")
    func neverReady() async {
        let size = SnapshotSize(name: "test", width: 20, height: 20)
        await #expect(throws: SnapshotError.notSettled("late.png", passes: 5)) {
            _ = try await SnapshotRenderer(maximumPasses: 5).render(
                Color.red, size: size, appearance: .light, chrome: .content, name: "late.png", isReady: { false })
        }
    }

    @Test("A rendering error names the file of the entry")
    func errorsNameTheFile() async {
        let entry = SnapshotEntry(
            name: "empty", sizes: [SnapshotSize(name: "zero", width: 0, height: 0)], appearances: [.light],
            chrome: .content
        ) { AnyView(Color.red) }
        await #expect(throws: SnapshotError.emptyImage("empty-light-zero.png")) {
            _ = try await SnapshotRenderer().renderings(of: entry, contrast: .standard)
        }
    }

    @Test("A standard pass skips contrast appearances, and a contrast pass renders only them")
    func passesSplitAppearances() async throws {
        let entry = SnapshotEntry(
            name: "split", sizes: [SnapshotSize(name: "s", width: 10, height: 10)],
            appearances: SnapshotAppearance.allCases, chrome: .content
        ) { AnyView(Color.red) }
        let files = try await SnapshotRenderer().renderings(of: entry, contrast: .standard).map(\.fileName)
        #expect(files == ["split-light-s.png", "split-dark-s.png"])
        await #expect(throws: SnapshotError.self) {
            _ = try await SnapshotRenderer().renderings(of: entry, contrast: .increased)
        }
    }

    @Test("PNG data starts with the PNG signature")
    func encodesPNG() async throws {
        let size = SnapshotSize(name: "test", width: 20, height: 20)
        let data = try await SnapshotRenderer().renderPNG(Color.blue, size: size, appearance: .light, chrome: .content)
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test("Every gallery page renders a non-empty image of its size in light and dark", arguments: GalleryPage.allCases)
    func galleryRenders(page: GalleryPage) async throws {
        var catalog = SnapshotCatalog()
        catalog.addComponentGallery()
        let entry = try #require(catalog.entries.first { $0.name == page.snapshotName })
        let renderer = SnapshotRenderer()
        for size in entry.sizes {
            for appearance in entry.appearances where appearance.contrast == .standard {
                let image = try await renderer.render(
                    entry.makeView(), size: size, appearance: appearance, chrome: entry.chrome)
                #expect(image.pixelsWide == Int(size.width * SnapshotRenderer.scale))
                if let height = size.height {
                    #expect(image.pixelsHigh == Int(height * SnapshotRenderer.scale))
                }
                #expect(ImageProbe(image).distinctColorCount() > 50, "\(page) \(appearance) is blank")
            }
        }
    }

    private func blueImage(_ size: SnapshotSize) async throws -> NSBitmapImageRep {
        try await SnapshotRenderer().render(Color.blue, size: size, appearance: .light, chrome: .content)
    }
}

/// Content that loads after a delay, as a page that loads in `.task` does.
@MainActor
@Observable
private final class LoadingModel {
    var isLoaded = false
}

private struct LoadingView: View {
    let model: LoadingModel

    var body: some View {
        (model.isLoaded ? Color.blue : Color.red)
            .task {
                try? await Task.sleep(for: .milliseconds(150))
                model.isLoaded = true
            }
    }
}

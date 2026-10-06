import AppKit
import SwiftUI
import Testing

@testable import JerdSnapshotSupport

@Suite("Snapshot scroll position")
@MainActor
struct SnapshotScrollTests {
    private let size = SnapshotSize(name: "test", width: 120, height: 100)

    /// A scroll view whose content is red at the top and blue at the end, three canvases tall.
    private var tallContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.red.frame(height: 200)
                Color.blue.frame(height: 100)
            }
        }
    }

    @Test("A top capture shows the start of a scroll view")
    func topShowsStart() async throws {
        let image = try await SnapshotRenderer().render(
            tallContent, size: size, appearance: .light, chrome: .content, scroll: .top)
        #expect(isRed(image), "The start of the content is red")
    }

    @Test("An end capture shows the end of a scroll view at the same canvas size")
    func endShowsEnd() async throws {
        let image = try await SnapshotRenderer().render(
            tallContent, size: size, appearance: .light, chrome: .content, scroll: .end)
        #expect(image.pixelsWide == 240)
        #expect(image.pixelsHigh == 200)
        let bottom = ImageProbe(image).components(x: 120, y: 190)
        #expect(bottom[2] > 200 && bottom[0] < 80, "The end of the content is blue, not \(bottom)")
    }

    @Test("Two end captures of one view have the same bytes, with no scroller")
    func endIsDeterministic() async throws {
        let renderer = SnapshotRenderer()
        let first = try await renderer.renderPNG(
            tallContent, size: size, appearance: .dark, chrome: .content, scroll: .end)
        let second = try await renderer.renderPNG(
            tallContent, size: size, appearance: .dark, chrome: .content, scroll: .end)
        #expect(first == second)
    }

    @Test("A scroll view whose content fits has no end position")
    func fittingContentDoesNotScroll() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        #expect(SnapshotScroller.endOrigin(of: scrollView) == nil)
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 300))
        #expect(SnapshotScroller.endOrigin(of: scrollView) != nil)
    }

    @Test("A catalog entry keeps its scroll position; the default is the top")
    func catalogKeepsScroll() {
        var catalog = SnapshotCatalog()
        catalog.add("page") { Text("Top") }
        catalog.add("page-end", scroll: .end) { Text("End") }
        #expect(catalog.entries.map(\.scroll) == [.top, .end])
    }

    private func isRed(_ image: NSBitmapImageRep) -> Bool {
        let pixel = ImageProbe(image).components(x: 120, y: 190)
        return pixel[0] > 200 && pixel[2] < 80
    }
}

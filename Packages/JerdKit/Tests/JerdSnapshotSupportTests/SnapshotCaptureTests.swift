import AppKit
import SwiftUI
import Testing

@testable import JerdSnapshotSupport

@Suite("Snapshot capture")
@MainActor
struct SnapshotCaptureTests {
    /// `cacheDisplay` marked the SwiftUI-hosted window buttons and the toolbar picker for layout,
    /// and they rendered again in the capture. Whether the picker did so depended on timing,
    /// so under load one rendering in about twenty had other text bounds in the toolbar.
    @Test("A capture only reads the window: no view needs layout after it")
    func captureDoesNotInvalidateLayout() async throws {
        let window = SnapshotWindow.make(
            size: CGSize(width: SnapshotSize.compact.width, height: SnapshotSize.compact.height ?? 0),
            chrome: .window(title: "Jerd"), appearance: NSAppearance(named: .aqua))
        defer { window.close() }
        let hostingView = NSHostingView(rootView: ComponentGallery(page: .workspace))
        hostingView.sceneBridgingOptions = [.toolbars, .title]
        hostingView.sizingOptions = []
        window.contentView = hostingView
        let frameView = try #require(window.contentView?.superview)
        for _ in 0..<4 {
            window.layoutIfNeeded()
            frameView.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(viewsNeedingLayout(in: frameView).isEmpty)

        _ = try #require(SnapshotRenderer().capture(frameView))

        #expect(viewsNeedingLayout(in: frameView).isEmpty)
    }

    private func viewsNeedingLayout(in view: NSView) -> [String] {
        (view.needsLayout ? ["\(type(of: view))"] : []) + view.subviews.flatMap { viewsNeedingLayout(in: $0) }
    }
}

import AppKit
import SwiftUI

/// Renders a SwiftUI view offscreen to a bitmap, without showing a window and without
/// screen recording permission. Output is at scale 2 and does not depend on the screen.
@MainActor
package struct SnapshotRenderer {
    /// Pixels per point in every snapshot, so output is the same on every Mac.
    package static let scale: CGFloat = 2

    /// Run loop turns that let SwiftUI finish layout, `ViewThatFits`, and toolbar bridging.
    private let settlePasses: Int

    package init(settlePasses: Int = 6) {
        self.settlePasses = settlePasses
    }

    /// Renders `content` in a window of exactly `size`, in the given appearance.
    package func render(
        _ content: some View, size: SnapshotSize, appearance: SnapshotAppearance, chrome: SnapshotChrome
    ) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let nsAppearance = NSAppearance(named: appearance.appearanceName)
        let hostingView = NSHostingView(rootView: SnapshotRoot(content: content, appearance: appearance))
        let window = SnapshotWindow.make(size: size.size, chrome: chrome, appearance: nsAppearance)
        hostingView.sceneBridgingOptions = [.toolbars, .title]
        // The canvas size is fixed; the view must not resize the window to its ideal size.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setFrame(NSRect(origin: .zero, size: size.size), display: false)
        defer { window.close() }

        let target = targetView(of: window, chrome: chrome, hostingView: hostingView)
        var image: NSBitmapImageRep?
        let draw = {
            self.settle(window: window, view: target)
            image = self.capture(target)
        }
        if let nsAppearance {
            nsAppearance.performAsCurrentDrawingAppearance(draw)
        } else {
            draw()
        }
        guard target.bounds.size == size.size else {
            throw SnapshotError.sizeMismatch(size.name, actual: target.bounds.size)
        }
        guard let image else { throw SnapshotError.emptyImage(size.name) }
        return image
    }

    /// Renders `content` and encodes the result as PNG data.
    package func renderPNG(
        _ content: some View, size: SnapshotSize, appearance: SnapshotAppearance, chrome: SnapshotChrome
    ) throws -> Data {
        let image = try render(content, size: size, appearance: appearance, chrome: chrome)
        guard let data = image.representation(using: .png, properties: [:]), !data.isEmpty else {
            throw SnapshotError.encodingFailed(size.name)
        }
        return data
    }

    /// The window frame view draws the titlebar and toolbar; the hosting view draws only content.
    private func targetView(of window: NSWindow, chrome: SnapshotChrome, hostingView: NSView) -> NSView {
        switch chrome {
        case .content: hostingView
        case .window: window.contentView?.superview ?? hostingView
        }
    }

    private func settle(window: NSWindow, view: NSView) {
        for _ in 0..<settlePasses {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            window.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            CATransaction.commit()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    private func capture(_ view: NSView) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
            let image = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * Self.scale),
                pixelsHigh: Int(bounds.height * Self.scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        image.size = bounds.size
        view.cacheDisplay(in: bounds, to: image)
        return image.retagging(with: .sRGB) ?? image
    }
}

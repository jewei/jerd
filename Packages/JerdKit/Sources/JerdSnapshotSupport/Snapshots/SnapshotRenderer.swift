import AppKit
import SwiftUI

/// Renders a SwiftUI view offscreen to a bitmap, without showing a window and without
/// screen recording permission. Output is at scale 2 and does not depend on the screen.
/// See `SnapshotProcessSettings` for the user settings that the snapshot process fixes.
@MainActor
package struct SnapshotRenderer {
    /// Pixels per point in every snapshot, so output is the same on every Mac.
    package static let scale: CGFloat = 2

    /// Layout passes before the renderer compares images, for `ViewThatFits` and toolbar bridging.
    package static let minimumPasses = 3

    /// The most layout passes before the renderer gives up on a view that never settles.
    private let maximumPasses: Int
    /// The time between passes. The renderer suspends, so main-actor work such as `.task` runs.
    private let passInterval: Duration

    package init(maximumPasses: Int = 150, passInterval: Duration = .milliseconds(20)) {
        self.maximumPasses = max(maximumPasses, Self.minimumPasses + 1)
        self.passInterval = passInterval
    }

    /// Renders `content` in a window of `size`, in the given appearance. The renderer runs
    /// layout passes until `isReady` is true and two passes in a row draw the same pixels.
    /// - Parameters:
    ///   - name: The file name of the rendering, for error messages.
    ///   - scroll: Where the scroll views stand in the capture.
    package func render(
        _ content: some View, size: SnapshotSize, appearance: SnapshotAppearance, chrome: SnapshotChrome,
        scroll: SnapshotScrollPosition = .top, name: String = "snapshot", isReady: @MainActor () -> Bool = { true }
    ) async throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let hostingView = NSHostingView(rootView: SnapshotRoot(content: content, appearance: appearance))
        let window = SnapshotWindow.make(
            size: CGSize(width: size.width, height: size.height ?? 1), chrome: chrome,
            appearance: NSAppearance(named: appearance.windowAppearanceName))
        defer { window.close() }
        try verifyAppearance(of: window, appearance: appearance, name: name)
        hostingView.sceneBridgingOptions = [.toolbars, .title]
        // The canvas size is fixed; the view must not resize the window to its ideal size.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        let target = targetView(of: window, chrome: chrome, hostingView: hostingView)

        try await resize(window, hostingView: hostingView, to: size, name: name, isReady: isReady)
        let image = try await settledImage(of: target, in: window, scroll: scroll, name: name, isReady: isReady)
        let expected = CGSize(width: size.width, height: size.height ?? target.bounds.height)
        guard target.bounds.size == expected else {
            throw SnapshotError.sizeMismatch(name, expected: expected, actual: target.bounds.size)
        }
        return image
    }

    /// Renders `content` and encodes the result as PNG data.
    package func renderPNG(
        _ content: some View, size: SnapshotSize, appearance: SnapshotAppearance, chrome: SnapshotChrome,
        scroll: SnapshotScrollPosition = .top, name: String = "snapshot", isReady: @MainActor () -> Bool = { true }
    ) async throws -> Data {
        let image = try await render(
            content, size: size, appearance: appearance, chrome: chrome, scroll: scroll, name: name,
            isReady: isReady)
        guard let data = image.representation(using: .png, properties: [:]), !data.isEmpty else {
            throw SnapshotError.encodingFailed(name)
        }
        return data
    }

    /// Refuses a rendering that would not show what the file name promises, for example an
    /// Increase Contrast file from a process where Increase Contrast is off.
    private func verifyAppearance(of window: NSWindow, appearance: SnapshotAppearance, name: String) throws {
        let candidates = SnapshotAppearance.allCases.map(\.resolvedAppearanceName)
        let resolved = window.effectiveAppearance.bestMatch(from: candidates)
        guard resolved == appearance.resolvedAppearanceName else {
            throw SnapshotError.appearanceUnavailable(
                name, expected: appearance.resolvedAppearanceName.rawValue,
                actual: resolved?.rawValue ?? window.effectiveAppearance.name.rawValue)
        }
    }

    /// Sets the window frame. A fitting height comes from the view's ideal height after it settles.
    private func resize(
        _ window: NSWindow, hostingView: NSHostingView<some View>, to size: SnapshotSize, name: String,
        isReady: @MainActor () -> Bool
    ) async throws {
        guard size.height == nil else {
            setContentSize(of: window, width: size.width, height: size.height ?? 0)
            return
        }
        // Only the intrinsic size option makes the hosting view report the ideal size of the view.
        hostingView.sizingOptions = [.intrinsicContentSize]
        defer { hostingView.sizingOptions = [] }
        for _ in 0..<3 {
            _ = try await settledImage(of: hostingView, in: window, scroll: .top, name: name, isReady: isReady)
            let height = hostingView.intrinsicContentSize.height.rounded(.up)
            guard height > 0, height != window.frame.height else { return }
            setContentSize(of: window, width: size.width, height: height)
        }
    }

    private func setContentSize(of window: NSWindow, width: CGFloat, height: CGFloat) {
        window.setFrame(NSRect(origin: .zero, size: CGSize(width: width, height: height)), display: false)
    }

    /// The window frame view draws the titlebar and toolbar; the hosting view draws only content.
    private func targetView(of window: NSWindow, chrome: SnapshotChrome, hostingView: NSView) -> NSView {
        switch chrome {
        case .content: hostingView
        case .window: window.contentView?.superview ?? hostingView
        }
    }

    /// Runs passes until the view is ready and two passes in a row draw the same pixels.
    private func settledImage(
        of view: NSView, in window: NSWindow, scroll: SnapshotScrollPosition, name: String,
        isReady: @MainActor () -> Bool
    ) async throws -> NSBitmapImageRep {
        var previous: NSBitmapImageRep?
        for pass in 1...maximumPasses {
            guard let image = drawPass(window: window, view: view, scroll: scroll) else {
                throw SnapshotError.emptyImage(name)
            }
            if pass >= Self.minimumPasses, isReady(), let previous, Self.samePixels(previous, image) {
                return image
            }
            previous = image
            // Suspending lets other main-actor work run, for example `.task` and its updates.
            try await Task.sleep(for: passInterval)
        }
        throw SnapshotError.notSettled(name, passes: maximumPasses)
    }

    /// Lays out and draws the window once, then captures `view`. For an end capture it scrolls
    /// after the layout, so the scroll target uses the current content height.
    private func drawPass(window: NSWindow, view: NSView, scroll: SnapshotScrollPosition) -> NSBitmapImageRep? {
        var image: NSBitmapImageRep?
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            window.layoutIfNeeded()
            if scroll == .end, let content = window.contentView {
                SnapshotScroller.scrollToEnd(in: content)
            }
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            CATransaction.commit()
            // One run loop turn for observers and timers that AppKit and SwiftUI schedule.
            RunLoop.current.run(until: Date())
            image = capture(view)
        }
        return image
    }
}

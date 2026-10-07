import AppKit

/// Moves the scroll views of a snapshot window to their end, without scroll events and without
/// animation, so two passes at the same layout draw the same pixels.
@MainActor
enum SnapshotScroller {
    /// Scrolls every vertical scroll view under `view` to its end. Views that cannot scroll stay.
    /// The renderer calls it before each pass, because content that loads late can grow.
    ///
    /// A scroll makes an overlay scroller appear and then fade out on a timer, so whether an
    /// image shows it would depend on how long the view takes to settle. The scrolled view hides
    /// its vertical scroller, as every top capture shows none.
    static func scrollToEnd(in view: NSView) {
        for scrollView in scrollViews(in: view) {
            let clip = scrollView.contentView
            guard let target = endOrigin(of: scrollView) else { continue }
            scrollView.verticalScroller?.isHidden = true
            guard clip.bounds.origin != target else { continue }
            clip.scroll(to: target)
            scrollView.reflectScrolledClipView(clip)
        }
    }

    /// The clip view origin that shows the end of the document, or nil when nothing scrolls.
    /// The insets keep content under a toolbar or above a bottom bar in view at the end.
    static func endOrigin(of scrollView: NSScrollView) -> NSPoint? {
        guard let document = scrollView.documentView else { return nil }
        let clip = scrollView.contentView
        let insets = clip.contentInsets
        let visibleHeight = clip.bounds.height
        let documentHeight = document.frame.height
        guard documentHeight + insets.top + insets.bottom > visibleHeight + 0.5 else { return nil }
        let endY =
            document.isFlipped
            ? document.frame.minY + documentHeight - visibleHeight + insets.bottom
            : document.frame.minY - insets.bottom
        return NSPoint(x: clip.bounds.origin.x, y: endY)
    }

    /// Every scroll view in the subtree of `view`, outermost first.
    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = view as? NSScrollView { result.append(scrollView) }
        for subview in view.subviews {
            result += scrollViews(in: subview)
        }
        return result
    }
}

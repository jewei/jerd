import AppKit

/// The sidebar column of the main window: a split with one item that has the `.sidebar`
/// behavior, so AppKit draws the system sidebar background itself.
///
/// Only a `.sidebar` item gets the system background: from macOS 26 it is a glass effect in a
/// variant that has no public API, and an `NSVisualEffectView` with the `.sidebar` material is
/// lighter (measured in dark mode: 53, and 88 over a light desktop, against 49 for the system
/// sidebar). The item has no sibling in its own split, so AppKit does not lay out the toolbar
/// after it: the section picker and the sidebar button keep their place. The outer split
/// (`WorkspaceSplitController`) owns the width, the collapse, and the splitter.
@MainActor
final class WorkspaceSidebarController: NSSplitViewController {
    /// The one item, with the system sidebar background.
    let backgroundItem: NSSplitViewItem

    init(content: NSViewController) {
        backgroundItem = NSSplitViewItem(sidebarWithViewController: WorkspaceColumnController(content: content))
        super.init(nibName: nil, bundle: nil)
        // The outer split collapses the column; this item only fills it, at every width.
        backgroundItem.canCollapse = false
        backgroundItem.minimumThickness = 0
        backgroundItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
        addSplitViewItem(backgroundItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

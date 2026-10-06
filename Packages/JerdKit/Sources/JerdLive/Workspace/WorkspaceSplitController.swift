import AppKit
import JerdDesign

/// The native split of the main window: the sidebar (the system sidebar background, full height
/// under the toolbar, the collapse animation, an accessible splitter, a saved width) and the
/// detail column.
///
/// The sidebar is a plain split item, not an item with the `.sidebar` behavior: from macOS 26,
/// AppKit lays out the whole window toolbar after a `.sidebar` item that has a sibling, so the
/// section picker and the sidebar button moved by the sidebar width each time the sidebar
/// collapsed (measured: the button from x 208 to 96). Both must stay in place, and
/// `WorkspaceSplitTests` checks it. The plain item holds `WorkspaceSidebarController`, a split
/// with one `.sidebar` item and no sibling, which gets the system sidebar background without
/// that toolbar layout. A window with a `.sidebar` item draws the title bar background (a hard
/// scroll edge) over a fixed page header, and without the split's own title bar areas that
/// background also covered the sidebar top; the split makes the title bar transparent, so the
/// sidebar background reaches the top edge as in a system sidebar.
///
/// The width of the sidebar is shared by every section and saved under `autosaveName`. The
/// sidebar visibility comes from `NavigationState`: `show(sidebarVisible:animated:)` applies it,
/// and a collapse that the user makes in the split itself (a drag of the divider) goes back
/// through `onSidebarCollapse`.
@MainActor
package final class WorkspaceSplitController: NSSplitViewController {
    /// Called when the user collapses (true) or expands (false) the sidebar in the split view.
    package var onSidebarCollapse: (@MainActor (Bool) -> Void)?
    package let sidebarItem: NSSplitViewItem
    /// The visibility that navigation asked for last. A collapse that differs from it is the user's.
    private var isSidebarRequested = true
    private var collapseObservation: NSKeyValueObservation?

    /// - Parameter autosaveName: The defaults name of the saved width; nil saves nothing.
    package init(sidebar: NSViewController, detail: NSViewController, autosaveName: String?) {
        sidebarItem = NSSplitViewItem(viewController: WorkspaceSidebarController(content: sidebar))
        super.init(nibName: nil, bundle: nil)
        sidebarItem.minimumThickness = WindowMetrics.sidebarMinimumWidth
        sidebarItem.maximumThickness = WindowMetrics.sidebarMaximumWidth
        sidebarItem.preferredThicknessFraction = WindowMetrics.sidebarIdealWidth / WindowMetrics.standardSize.width
        // The sidebar keeps its width when the window resizes; the detail column takes the rest.
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue + 10)
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        // The name must be set before the items, so the split restores the saved width.
        splitView.autosaveName = autosaveName
        splitView.dividerStyle = .thin
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: WorkspaceColumnController(content: detail)))
        collapseObservation = sidebarItem.observe(\.isCollapsed, options: [.new]) { [weak self] _, change in
            guard let isCollapsed = change.newValue else { return }
            // AppKit changes the split geometry on the main thread.
            MainActor.assumeIsolated { self?.sidebarCollapseChanged(isCollapsed) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows or hides the sidebar. The sidebar button and ⌃⌘S animate, like every macOS
    /// sidebar; a section change does not, so the new section shows in one frame.
    package func show(sidebarVisible isVisible: Bool, animated: Bool) {
        isSidebarRequested = isVisible
        guard sidebarItem.isCollapsed == isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.allowsImplicitAnimation = true
                sidebarItem.animator().isCollapsed = !isVisible
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sidebarItem.isCollapsed = !isVisible
            view.layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
    }

    override package func viewDidLayout() {
        super.viewDidLayout()
        makeTitlebarTransparent()
        limitSidebarWidth()
    }

    /// The sidebar and the page headers continue under the toolbar, without a title bar band.
    private func makeTitlebarTransparent() {
        guard let window = view.window, !window.titlebarAppearsTransparent else { return }
        window.titlebarAppearsTransparent = true
    }

    /// Keeps the sidebar edge away from the centered section picker in a narrow window.
    private func limitSidebarWidth() {
        guard let window = view.window, let picker = window.toolbar?.centeredItemView else { return }
        let widths = SidebarWidthLimit.widths(windowWidth: window.frame.width, pickerWidth: picker.frame.width)
        if sidebarItem.minimumThickness != widths.lowerBound { sidebarItem.minimumThickness = widths.lowerBound }
        if sidebarItem.maximumThickness != widths.upperBound { sidebarItem.maximumThickness = widths.upperBound }
    }

    private func sidebarCollapseChanged(_ isCollapsed: Bool) {
        guard isCollapsed == isSidebarRequested else { return }
        isSidebarRequested = !isCollapsed
        onSidebarCollapse?(isCollapsed)
    }
}

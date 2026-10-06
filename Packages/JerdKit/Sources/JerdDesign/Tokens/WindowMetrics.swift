import CoreGraphics

/// Sizes of the main window and its sidebar. Every page must work at both window sizes.
public enum WindowMetrics {
    /// The smallest main window. Pages must not clip or overlap at this size.
    public static let minimumSize = CGSize(width: 820, height: 540)

    /// The size of a new main window.
    public static let standardSize = CGSize(width: 980, height: 660)

    /// The height of the unified toolbar above the content. The window minimum is a window
    /// size, so the content may use only what the toolbar leaves.
    public static let toolbarHeight: CGFloat = 52

    /// The smallest content: the minimum window less the toolbar. The app scene uses
    /// `.windowResizability(.contentMinSize)`, so the window never gets smaller than
    /// `minimumSize` and never clips the bottom of a page or a sidebar footer.
    public static let minimumContentSize = CGSize(
        width: minimumSize.width, height: minimumSize.height - toolbarHeight)

    public static let sidebarMinimumWidth: CGFloat = 200
    public static let sidebarIdealWidth: CGFloat = 220
    public static let sidebarMaximumWidth: CGFloat = 280
}

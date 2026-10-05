import CoreGraphics

/// Sizes of the main window and its sidebar. Every page must work at both window sizes.
public enum WindowMetrics {
    /// The smallest main window. Pages must not clip or overlap at this size.
    public static let minimumSize = CGSize(width: 820, height: 540)

    /// The size of a new main window.
    public static let standardSize = CGSize(width: 980, height: 660)

    public static let sidebarMinimumWidth: CGFloat = 200
    public static let sidebarIdealWidth: CGFloat = 220
    public static let sidebarMaximumWidth: CGFloat = 280
}

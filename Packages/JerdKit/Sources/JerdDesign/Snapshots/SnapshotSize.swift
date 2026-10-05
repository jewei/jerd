import CoreGraphics

/// A named canvas size for a snapshot. The name is part of the file name.
package struct SnapshotSize: Hashable, Sendable {
    package let name: String
    package let width: CGFloat
    package let height: CGFloat

    package init(name: String, width: CGFloat, height: CGFloat) {
        self.name = name
        self.width = width
        self.height = height
    }

    package var size: CGSize { CGSize(width: width, height: height) }

    /// The default size of the main window.
    package static let standard = SnapshotSize(
        name: "standard", width: WindowMetrics.standardSize.width, height: WindowMetrics.standardSize.height)

    /// The minimum size of the main window.
    package static let compact = SnapshotSize(
        name: "compact", width: WindowMetrics.minimumSize.width, height: WindowMetrics.minimumSize.height)

    /// Both window sizes that every page must support.
    package static let windowSizes: [SnapshotSize] = [.standard, .compact]
}

import CoreGraphics
import JerdDesign

/// A named canvas size for a snapshot. The name is part of the file name.
package struct SnapshotSize: Hashable, Sendable {
    package let name: String
    package let width: CGFloat
    /// The canvas height, or nil when the canvas takes the ideal height of the view at `width`,
    /// for example a sheet whose height follows its content.
    package let height: CGFloat?

    package init(name: String, width: CGFloat, height: CGFloat?) {
        self.name = name
        self.width = width
        self.height = height
    }

    /// A canvas of `width` whose height is the ideal height of the view.
    package static func fittingHeight(name: String, width: CGFloat) -> SnapshotSize {
        SnapshotSize(name: name, width: width, height: nil)
    }

    /// The default size of the main window.
    package static let standard = SnapshotSize(
        name: "standard", width: WindowMetrics.standardSize.width, height: WindowMetrics.standardSize.height)

    /// The minimum size of the main window.
    package static let compact = SnapshotSize(
        name: "compact", width: WindowMetrics.minimumSize.width, height: WindowMetrics.minimumSize.height)

    /// Both window sizes that every page must support.
    package static let windowSizes: [SnapshotSize] = [.standard, .compact]

    /// For `--list`, for example `standard 980×660` or `sheet 540×fit`.
    package var listDescription: String {
        "\(name) \(Int(width))×\(height.map { String(Int($0)) } ?? "fit")"
    }
}

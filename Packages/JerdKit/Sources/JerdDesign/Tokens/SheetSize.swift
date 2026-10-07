import CoreGraphics

/// Standard sheet sizes. A sheet has a fixed width. Its height follows its content between a
/// minimum and a maximum, so no caller sets a height by hand. Longer content scrolls.
/// Each maximum fits under the toolbar of the smallest main window (540 pt high).
public struct SheetSize: Hashable, Sendable {
    public let width: CGFloat
    public let minimumHeight: CGFloat
    public let maximumHeight: CGFloat

    public init(width: CGFloat, minimumHeight: CGFloat, maximumHeight: CGFloat) {
        self.width = width
        self.minimumHeight = minimumHeight
        self.maximumHeight = max(minimumHeight, maximumHeight)
    }

    /// A short confirmation or a form with one or two fields.
    public static let compact = SheetSize(width: 440, minimumHeight: 180, maximumHeight: 360)
    /// An editor with a few sections, for example a site or a service.
    public static let standard = SheetSize(width: 540, minimumHeight: 260, maximumHeight: 480)
    /// An editor or log with wide content.
    public static let wide = SheetSize(width: 640, minimumHeight: 320, maximumHeight: 480)
}

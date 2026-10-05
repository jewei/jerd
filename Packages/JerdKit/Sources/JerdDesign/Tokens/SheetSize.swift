import CoreGraphics

/// Standard sheet sizes. A sheet has a fixed width and grows with its content from a minimum
/// height, so no caller sets a height by hand.
public struct SheetSize: Hashable, Sendable {
    public let width: CGFloat
    public let minimumHeight: CGFloat
    public let idealHeight: CGFloat

    public init(width: CGFloat, minimumHeight: CGFloat, idealHeight: CGFloat) {
        self.width = width
        self.minimumHeight = minimumHeight
        self.idealHeight = max(minimumHeight, idealHeight)
    }

    /// A short confirmation or a form with one or two fields.
    public static let compact = SheetSize(width: 440, minimumHeight: 220, idealHeight: 280)
    /// An editor with a few sections, for example a site or a service.
    public static let standard = SheetSize(width: 540, minimumHeight: 360, idealHeight: 480)
    /// An editor or log with wide content.
    public static let wide = SheetSize(width: 640, minimumHeight: 420, idealHeight: 520)
}

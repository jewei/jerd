import CoreGraphics

/// Corner radii. Every rounded shape uses the continuous corner style.
public enum Radius {
    /// Small containers inside a row.
    public static let small: CGFloat = 6
    /// Banners and toasts that sit next to grouped form sections.
    public static let medium: CGFloat = 10
    /// Dashboard cards and selectable tiles.
    public static let large: CGFloat = 14

    /// The radius of a symbol tile, in proportion to its side, like an app icon.
    public static func iconTile(side: CGFloat) -> CGFloat {
        (side * 0.27).rounded()
    }
}

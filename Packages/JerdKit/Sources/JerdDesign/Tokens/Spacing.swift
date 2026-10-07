import CoreGraphics

/// The spacing scale. Use these values for every padding and stack spacing, so the rhythm is
/// the same on every page.
public enum Spacing {
    /// Between a title and its one-line detail.
    public static let hairline: CGFloat = 2
    /// Between a symbol and its label, and inside badges.
    public static let tight: CGFloat = 4
    /// Between controls in a row.
    public static let small: CGFloat = 8
    /// Between a row's text and its controls.
    public static let medium: CGFloat = 12
    /// Inside cards and banners, and between cards.
    public static let large: CGFloat = 16
    /// Above and below a page header.
    public static let extraLarge: CGFloat = 20
    /// Between page sections outside a form.
    public static let section: CGFloat = 24
    /// Around a centered empty state.
    public static let page: CGFloat = 32
}

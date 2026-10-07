import CoreGraphics

/// The horizontal layout of a page. The page header, banners, grouped form sections, and
/// cards share one centered column, so their edges and text line up at every width.
public enum PageMetrics {
    /// The widest content column. It is narrower than the system grouped-form limit (704 pt
    /// on macOS 26 and later), so Jerd, not the system, decides the column on every macOS version.
    public static let maximumContentWidth: CGFloat = 680

    /// The inset that a grouped `Form` always adds at each side of its sections.
    public static let formInset: CGFloat = 20

    /// The inset of row text inside a grouped form section.
    public static let rowInset: CGFloat = 10

    /// The horizontal inset of content inside a dashboard card. It equals `rowInset`, so card
    /// content starts on the same text column as the page title and form rows.
    public static let cardInset: CGFloat = rowInset

    /// The columns for a page of the given width.
    public static func columns(forWidth width: CGFloat) -> PageColumns {
        let available = max(0, width - 2 * formInset)
        let contentWidth = min(available, maximumContentWidth)
        let formMargin = ((available - contentWidth) / 2).rounded(.down)
        return PageColumns(
            contentWidth: contentWidth,
            sectionInset: formInset + formMargin,
            formMargin: formMargin,
            textInset: formInset + formMargin + rowInset)
    }
}

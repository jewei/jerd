import CoreGraphics

/// The computed columns of one page width. See `PageMetrics.columns(forWidth:)`.
public struct PageColumns: Hashable, Sendable {
    /// The width of grouped sections and cards.
    public let contentWidth: CGFloat
    /// The distance from the page edge to the edge of a section or card.
    public let sectionInset: CGFloat
    /// The extra margin that a grouped `Form` needs, added to its own `formInset`.
    public let formMargin: CGFloat
    /// The distance from the page edge to row text, the page title, and section headers.
    public let textInset: CGFloat
}

import CoreGraphics

/// Opacity values for tinted fills and strokes. Text never uses these; it uses semantic
/// foreground styles, so contrast stays correct.
public enum Opacity {
    /// The fill behind a tinted symbol tile or a status badge.
    public static let tintFill: CGFloat = 0.12
    /// The fill behind a banner, which holds body text and must stay calm.
    public static let bannerFill: CGFloat = 0.08
    /// The outline of a tinted shape.
    public static let tintStroke: CGFloat = 0.22
    /// The outline of a tinted shape when Increase Contrast is on.
    public static let tintStrokeIncreasedContrast: CGFloat = 0.7
    /// The fill of a neutral card, as a primary-color overlay. It matches grouped form sections.
    public static let cardFill: CGFloat = 0.03
    /// The outline of a neutral card.
    public static let cardStroke: CGFloat = 0.5
    /// The outline of a neutral card when Increase Contrast is on.
    public static let cardStrokeIncreasedContrast: CGFloat = 1
}

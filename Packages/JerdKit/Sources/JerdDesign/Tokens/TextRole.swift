import SwiftUI

/// The role of a piece of text. Each role maps to a system text style, so Dynamic Type and
/// future system font changes apply everywhere. Use roles, never point sizes.
public enum TextRole: CaseIterable, Sendable {
    /// The title of a page header.
    case pageTitle
    /// The title of a sheet.
    case sheetTitle
    /// The title of a dashboard card.
    case cardTitle
    /// The main text of a row.
    case rowTitle
    /// Secondary text under a row title, in footers, and in summaries.
    case detail
    /// Small counts and notes, for example in a sidebar footer.
    case caption
    /// The label in a status badge.
    case badge
    /// A technical value such as a path, a port, or a fingerprint.
    case code

    public var font: Font {
        switch self {
        case .pageTitle: .title.weight(.semibold)
        case .sheetTitle: .title2.weight(.semibold)
        case .cardTitle: .title3.weight(.semibold)
        case .rowTitle: .body
        case .detail: .callout
        case .caption: .caption
        case .badge: .subheadline.weight(.medium)
        case .code: .body.monospaced()
        }
    }

    /// Titles are headers for VoiceOver navigation.
    public var isHeader: Bool {
        switch self {
        case .pageTitle, .sheetTitle, .cardTitle: true
        default: false
        }
    }

    /// Detail and caption text is secondary; every other role uses the primary color.
    public var isSecondary: Bool {
        switch self {
        case .detail, .caption: true
        default: false
        }
    }
}

extension View {
    /// Applies the font, color, and header trait of a text role.
    public func textRole(_ role: TextRole) -> some View {
        font(role.font)
            .foregroundStyle(role.isSecondary ? HierarchicalShapeStyle.secondary : .primary)
            .accessibilityAddTraits(role.isHeader ? .isHeader : [])
    }
}

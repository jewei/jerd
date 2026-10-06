import JerdDesign
import SwiftUI

/// The row of a form section without items: a symbol, what is missing, and the next step.
struct EmptySectionRow: View {
    /// The symbol column of `InlineMessage`, so both kinds of row start their text at one place.
    private static let symbolWidth: CGFloat = 16

    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: Self.symbolWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(title)
                    .textRole(.rowTitle)
                Text(detail)
                    .textRole(.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}


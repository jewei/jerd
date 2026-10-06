import JerdDesign
import SwiftUI

/// Shows a `ConnectionValue`: a `ValueRow` with its copy button, or a description whose hidden
/// copy button keeps the gutter of the section.
struct ConnectionValueRow: View {
    let value: ConnectionValue

    var body: some View {
        if let copy = value.copy {
            ValueRow(value.label, value: value.value, isCode: true, copy: copy)
        } else {
            LabeledContent {
                HStack(spacing: Spacing.small) {
                    Text(value.value)
                        .font(TextRole.rowTitle.font)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityLabel(value.label)
                        .accessibilityValue(value.value)
                    // Only takes the width of the copy buttons of the other rows.
                    CopyButton(subject: value.label) {}
                        .hidden()
                        .accessibilityHidden(true)
                }
            } label: {
                Text(value.label)
            }
        }
    }
}

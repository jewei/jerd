import SwiftUI

/// A label and a read-only value in a grouped form. Long values truncate in the middle and
/// show in full as a tooltip. The value is selectable, and an optional button copies it.
public struct ValueRow: View {
    private let label: String
    private let value: String
    private let isCode: Bool
    private let copy: (@MainActor () -> Void)?

    /// - Parameters:
    ///   - isCode: Uses the monospaced font for technical values such as hosts, ports, and keys.
    ///   - copy: Copies the value. The caller writes to the pasteboard and shows `CopyFeedback`.
    public init(_ label: String, value: String, isCode: Bool = false, copy: (@MainActor () -> Void)? = nil) {
        self.label = label
        self.value = value
        self.isCode = isCode
        self.copy = copy
    }

    public var body: some View {
        LabeledContent {
            HStack(spacing: Spacing.small) {
                Text(value)
                    .font(isCode ? TextRole.code.font : TextRole.rowTitle.font)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(value)
                    .accessibilityLabel(label)
                    .accessibilityValue(value)
                if let copy {
                    CopyButton(subject: label, perform: copy)
                }
            }
        } label: {
            Text(label)
        }
    }
}

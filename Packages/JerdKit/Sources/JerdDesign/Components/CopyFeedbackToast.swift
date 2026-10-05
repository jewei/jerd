import SwiftUI

/// The capsule that `copyFeedback(_:)` shows. Public so pages can preview it.
public struct CopyFeedbackToast: View {
    private let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(StatusTone.ready.color)
        }
        .font(TextRole.detail.font.weight(.medium))
        .padding(.horizontal, Spacing.medium + Spacing.hairline)
        .padding(.vertical, Spacing.small)
        .background { Capsule(style: .circular).fill(.regularMaterial) }
        .overlay { Capsule(style: .circular).strokeBorder(.separator) }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

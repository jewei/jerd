import SwiftUI

/// A capsule with a status symbol and label, for page headers and dashboard cards.
/// Show one badge per subject per page; rows below explain what the status means.
public struct StatusBadge: View {
    private let status: DisplayStatus
    private let accessibilitySubject: String
    @Environment(\.colorSchemeContrast) private var contrast

    /// - Parameter accessibilityLabel: The subject of the status, for example "Site status".
    public init(_ label: String, tone: StatusTone, accessibilityLabel: String) {
        self.init(DisplayStatus(label, tone: tone), accessibilityLabel: accessibilityLabel)
    }

    public init(_ status: DisplayStatus, accessibilityLabel: String) {
        self.status = status
        self.accessibilitySubject = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: Spacing.tight) {
            StatusSymbol(tone: status.tone)
            Text(status.label)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .font(TextRole.badge.font)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, 3)
        .background { Capsule(style: .circular).fill(status.tone.color.opacity(Opacity.tintFill)) }
        .overlay {
            Capsule(style: .circular).strokeBorder(status.tone.color.opacity(strokeOpacity))
        }
        .fixedSize()
        .help(status.spokenDescription(subject: accessibilitySubject))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySubject)
        .accessibilityValue(status.label)
    }

    private var strokeOpacity: CGFloat {
        contrast == .increased ? Opacity.tintStrokeIncreasedContrast : Opacity.tintStroke
    }
}

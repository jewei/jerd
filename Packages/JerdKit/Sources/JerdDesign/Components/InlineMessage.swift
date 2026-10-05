import SwiftUI

/// A message with a symbol, text, an optional action, and an optional Dismiss button.
/// Use the row style inside a form section and the banner style at the top of a page.
/// Warnings and errors in the banner style are announced to VoiceOver when they appear.
public struct InlineMessage: View {
    /// Where the message is shown.
    public enum Style: Sendable {
        /// A plain form row.
        case row
        /// A tinted, rounded banner on the page column.
        case banner
    }

    private let text: String
    private let kind: MessageKind
    private let title: String?
    private let style: Style
    private let action: PageAction?
    private let dismiss: (@MainActor () -> Void)?
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        _ text: String, kind: MessageKind, title: String? = nil, style: Style = .row, action: PageAction? = nil,
        dismiss: (@MainActor () -> Void)? = nil
    ) {
        self.text = text
        self.kind = kind
        self.title = title
        self.style = style
        self.action = action
        self.dismiss = dismiss
    }

    public var body: some View {
        switch style {
        case .row:
            content
        case .banner:
            content
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small + Spacing.hairline)
                .background { bannerShape.fill(kind.color.opacity(Opacity.bannerFill)) }
                .overlay { bannerShape.strokeBorder(kind.color.opacity(strokeOpacity)) }
                .onAppear(perform: announce)
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            message
            if let action {
                PageActionButton(action: action, isPrimary: false)
                    .controlSize(.small)
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .accessibilityLabel("Dismiss \(kind.spokenName.lowercased())")
            }
        }
        .font(TextRole.detail.font)
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: kind.systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(kind.color)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                if let title {
                    Text(title).fontWeight(.semibold)
                }
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    /// The text VoiceOver reads, starting with the kind, for example "Error: …".
    var spokenText: String {
        [kind.spokenName, title, text].compactMap { $0 }.joined(separator: ": ")
    }

    private var bannerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
    }

    private var strokeOpacity: CGFloat {
        contrast == .increased ? Opacity.tintStrokeIncreasedContrast : Opacity.tintStroke
    }

    private func announce() {
        guard kind.isAnnounced else { return }
        AccessibilityNotification.Announcement(spokenText).post()
    }
}

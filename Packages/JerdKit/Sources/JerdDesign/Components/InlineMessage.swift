import SwiftUI

/// A message with a symbol, text, up to two actions, and an optional Dismiss button.
/// Use the row style inside a form section and the banner style at the top of a page.
/// Warnings and errors are announced to VoiceOver when they appear and each time their text
/// changes, in both styles.
public struct InlineMessage: View {
    /// Where the message is shown.
    public enum Style: Sendable {
        /// A plain form row.
        case row
        /// A tinted, rounded banner on the page column.
        case banner
    }

    /// The width of the symbol column, so the text starts at one place for every kind.
    static let symbolWidth: CGFloat = 16
    /// The height of one line of banner content, with or without a small button, so every banner
    /// with one line of text has the same height.
    static let bannerLineHeight: CGFloat = 22

    private let text: String
    private let kind: MessageKind
    private let title: String?
    private let style: Style
    private let action: PageAction?
    private let secondaryAction: PageAction?
    private let identifier: String?
    private let dismiss: (@MainActor () -> Void)?
    let details: InlineMessageDetails?
    @State private var showsDetails: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.messageAnnouncer) private var announcer

    /// - Parameters:
    ///   - identifier: The stable name of the message for UI tests. The Dismiss button
    ///     gets `<identifier>.dismiss`; without it, `message.<kind>.dismiss`.
    ///   - details: Lines below the text behind a disclosure, for example the end of a log. The
    ///     disclosure gets `<identifier>.details`.
    ///   - secondaryAction: A second button after `action`, for a follow-up step such as Check Again.
    public init(
        _ text: String, kind: MessageKind, title: String? = nil, style: Style = .row, action: PageAction? = nil,
        secondaryAction: PageAction? = nil, identifier: String? = nil, details: InlineMessageDetails? = nil,
        dismiss: (@MainActor () -> Void)? = nil
    ) {
        self.text = text
        self.kind = kind
        self.title = title
        self.style = style
        self.action = action
        self.secondaryAction = secondaryAction
        self.identifier = identifier
        self.dismiss = dismiss
        self.details = details?.lines.isEmpty == false ? details : nil
        _showsDetails = State(initialValue: details?.isExpanded ?? false)
    }

    public var body: some View {
        styled
            .onChange(of: spokenText, initial: true) { _, newText in
                guard kind.isAnnounced else { return }
                announcer.announce(newText)
            }
    }

    @ViewBuilder private var styled: some View {
        switch style {
        case .row:
            content
        case .banner:
            content
                .frame(minHeight: Self.bannerLineHeight)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.small)
                .background { bannerShape.fill(kind.color.opacity(Opacity.bannerFill)) }
                .overlay { bannerShape.strokeBorder(kind.color.opacity(strokeOpacity)) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            mainLine
            if let details {
                detailsDisclosure(details)
            }
        }
        .font(TextRole.detail.font)
        .accessibilityElement(children: .contain)
    }

    private func detailsDisclosure(_ details: InlineMessageDetails) -> some View {
        DisclosureGroup(details.title, isExpanded: $showsDetails) {
            Text(details.lines.joined(separator: "\n"))
                .font(TextRole.detail.font.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Self.symbolWidth + Spacing.small)
        .accessibilityIdentifier(detailsIdentifier)
    }

    private var mainLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            message
            if let action {
                PageActionButton(action: action, isPrimary: false)
                    .controlSize(.small)
            }
            if let secondaryAction {
                PageActionButton(action: secondaryAction, isPrimary: false)
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
                .accessibilityIdentifier(dismissIdentifier)
            }
        }
    }

    private var message: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: kind.systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(kind.color)
                .frame(width: Self.symbolWidth)
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

    /// The identifier of the Dismiss button.
    var dismissIdentifier: String {
        identifier.map { "\($0).dismiss" } ?? AccessibilityIdentifier.make("message", kind.rawValue, "dismiss")
    }

    /// The identifier of the details disclosure.
    var detailsIdentifier: String {
        identifier.map { "\($0).details" } ?? AccessibilityIdentifier.make("message", kind.rawValue, "details")
    }

    private var bannerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
    }

    private var strokeOpacity: CGFloat {
        contrast == .increased ? Opacity.tintStrokeIncreasedContrast : Opacity.tintStroke
    }
}

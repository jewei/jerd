import SwiftUI

/// Fits one regular push button, so cards with and without actions have the same height.
private let footerHeight: CGFloat = 24

/// A dashboard card for one area: icon, title, status, a two-line summary, the area's quick
/// actions, and an Open button. The Open button keeps the footer from ever being empty.
/// VoiceOver treats the card as one container named by its title.
public struct SummaryCard<Actions: View>: View {
    private let title: String
    private let systemImage: String
    private let tint: ServiceTint
    private let status: DisplayStatus
    private let summary: String
    private let open: @MainActor () -> Void
    private let actions: Actions
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        _ title: String, systemImage: String, tint: ServiceTint, status: DisplayStatus, summary: String,
        open: @escaping @MainActor () -> Void, @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.status = status
        self.summary = summary
        self.open = open
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Text(summary)
                .textRole(.detail)
                .lineLimit(2, reservesSpace: true)
                .help(summary)
                .padding(.top, Spacing.medium)
            Divider()
                .padding(.vertical, Spacing.medium)
            footer
        }
        .padding(Spacing.large)
        .background { cardShape.fill(.primary.opacity(Opacity.cardFill)) }
        .overlay { cardShape.strokeBorder(.separator.opacity(strokeOpacity)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            ServiceIcon(systemImage: systemImage, tint: tint, size: .large)
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(title)
                    .textRole(.cardTitle)
                    .lineLimit(1)
                StatusBadge(status, accessibilityLabel: "\(title) status")
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.small) {
            actions
            Spacer(minLength: Spacing.small)
            Button(action: open) {
                HStack(spacing: Spacing.tight) {
                    Text("Open")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.borderless)
            .help("Open \(title)")
            .accessibilityLabel("Open \(title)")
        }
        .controlSize(.regular)
        .frame(minHeight: footerHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
    }

    private var strokeOpacity: CGFloat {
        contrast == .increased ? Opacity.cardStrokeIncreasedContrast : Opacity.cardStroke
    }
}

import JerdDesign
import SwiftUI

/// The runtimes row under the dashboard cards: the default PHP and a link to Runtimes.
struct RuntimesSummaryRow: View {
    let defaultPHPVersion: String?
    let manage: @MainActor () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            ServiceIcon(systemImage: "shippingbox", tint: .runtimes, size: .large)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text("Runtimes")
                    .textRole(.cardTitle)
                Text(Self.detail(defaultPHPVersion: defaultPHPVersion))
                    .textRole(.detail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Spacing.medium)
            Button("Manage Runtimes", action: manage)
                .help("Manage runtimes")
                .accessibilityIdentifier("dashboard.runtimes.manage")
        }
        .padding(.horizontal, PageMetrics.cardInset)
        .padding(.vertical, Spacing.medium)
        .background { shape.fill(.primary.opacity(Opacity.cardFill)) }
        .overlay {
            shape.strokeBorder(
                .separator.opacity(contrast == .increased ? Opacity.cardStrokeIncreasedContrast : Opacity.cardStroke))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Runtimes")
    }

    /// The detail line, with the default PHP when one is registered.
    static func detail(defaultPHPVersion: String?) -> String {
        let base = "View installed versions and check for updates."
        guard let defaultPHPVersion else { return base }
        return "PHP \(defaultPHPVersion) is the default. \(base)"
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
    }
}

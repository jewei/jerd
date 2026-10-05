import SwiftUI

/// A two-line sidebar row with a trailing status symbol. VoiceOver reads it as one element:
/// the title, then the subtitle and status.
public struct SidebarRow: View {
    private let title: String
    private let subtitle: String?
    private let status: DisplayStatus?
    private let isDimmed: Bool

    /// - Parameter isDimmed: Shows a disabled item, for example a site that is turned off.
    public init(_ title: String, subtitle: String? = nil, status: DisplayStatus? = nil, isDimmed: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.isDimmed = isDimmed
    }

    public var body: some View {
        HStack(spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(title)
                    .fontWeight(.medium)
                    .foregroundStyle(isDimmed ? .secondary : .primary)
                if let subtitle {
                    Text(subtitle)
                        .textRole(.caption)
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let status {
                StatusIndicator(status)
            }
        }
        .padding(.vertical, Spacing.tight)
        .help(title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spokenValue)
    }

    /// The subtitle and status, for example "studio.test, Ready".
    var spokenValue: String {
        [subtitle, status?.label].compactMap { $0 }.joined(separator: ", ")
    }
}

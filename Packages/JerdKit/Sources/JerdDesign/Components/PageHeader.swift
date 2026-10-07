import SwiftUI

/// The fixed header of a page: title, optional subtitle, one status badge, and actions.
/// The type allows at most one primary action. When the width is too small for one line,
/// the actions move below the title.
public struct PageHeader<Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    let status: NamedStatus?
    private let primaryAction: PageAction?
    private let secondaryActions: [PageAction]
    private let accessory: Accessory

    /// - Parameters:
    ///   - status: The one status badge of the page, with its spoken subject, for example
    ///     `NamedStatus("Site status", DisplayStatus("Ready", tone: .ready))`.
    ///   - secondaryActions: Shown before the primary action, in the given order.
    ///   - accessory: Extra trailing content, for example a `BusyIndicator` or a `Menu`.
    public init(
        _ title: String, subtitle: String? = nil, status: NamedStatus? = nil,
        primaryAction: PageAction? = nil, secondaryActions: [PageAction] = [],
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.accessory = accessory()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.large) {
                titleBlock.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                actionRow
            }
            VStack(alignment: .leading, spacing: Spacing.medium) {
                titleBlock
                actionRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            HStack(alignment: .center, spacing: Spacing.small) {
                Text(title)
                    .textRole(.pageTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(title)
                if let status {
                    StatusBadge(status.status, accessibilityLabel: status.subject)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .textRole(.detail)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(subtitle)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: Spacing.small) {
            accessory
            // Actions are keyed by position: two actions may share a title.
            ForEach(secondaryActions.indices, id: \.self) { index in
                PageActionButton(action: secondaryActions[index], isPrimary: false)
            }
            if let primaryAction {
                PageActionButton(action: primaryAction, isPrimary: true)
            }
        }
        .controlSize(.regular)
        .fixedSize()
    }
}

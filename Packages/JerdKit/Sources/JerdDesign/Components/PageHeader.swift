import SwiftUI

/// The fixed header of a page: title, optional subtitle, one status badge, and actions.
/// The type allows at most one primary action. When the width is too small for one line,
/// the actions move below the title.
public struct PageHeader<Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let status: DisplayStatus?
    private let statusSubject: String
    private let primaryAction: PageAction?
    private let secondaryActions: [PageAction]
    private let accessory: Accessory

    /// - Parameters:
    ///   - statusSubject: The spoken subject of the badge, for example "Site status".
    ///   - secondaryActions: Shown before the primary action, in the given order.
    ///   - accessory: Extra trailing content, for example a `BusyIndicator` or a `Menu`.
    public init(
        _ title: String, subtitle: String? = nil, status: DisplayStatus? = nil, statusSubject: String = "Status",
        primaryAction: PageAction? = nil, secondaryActions: [PageAction] = [],
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.statusSubject = statusSubject
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
                    StatusBadge(status, accessibilityLabel: statusSubject)
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
            ForEach(secondaryActions) { action in
                PageActionButton(action: action, isPrimary: false)
            }
            if let primaryAction {
                PageActionButton(action: primaryAction, isPrimary: true)
            }
        }
        .controlSize(.regular)
        .fixedSize()
    }
}

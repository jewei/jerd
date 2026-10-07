import SwiftUI

/// A form row with a title, optional detail, and trailing controls. Unlike `LabeledContent`,
/// it keeps the spoken name of each control.
public struct ActionRow<Actions: View>: View {
    private let title: String
    private let detail: String?
    private let actions: Actions

    public init(_ title: String, detail: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(title)
                    .textRole(.rowTitle)
                if let detail {
                    Text(detail)
                        .textRole(.detail)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.small) {
                actions
            }
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
    }
}

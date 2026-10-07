import JerdDesign
import SwiftUI

/// The dashboard card of one section, from its feature summary. `CardActionRule` keeps the
/// actions short, so they stand in one row on every card at the minimum window size; only a
/// larger text size puts them in a column. A card never drops an action, never hides one in a
/// menu, and never truncates a button title.
struct FeatureCard: View {
    /// How the actions stand, in the order the card tries them.
    enum ActionLayout: CaseIterable {
        /// Every action as a button, in one row.
        case row
        /// Every action as a button, one per line.
        case column
    }

    let section: AppSection
    let summary: FeatureSummary
    let open: @MainActor () -> Void

    var body: some View {
        SummaryCard(
            section.title, systemImage: section.systemImage, tint: section.tint, status: summary.status,
            summary: summary.summary, identifier: AccessibilityIdentifier.make("dashboard", section.title), open: open
        ) {
            ViewThatFits(in: .horizontal) {
                ForEach(ActionLayout.allCases, id: \.self) { layout in
                    actions(in: layout)
                }
            }
        }
    }

    @ViewBuilder func actions(in layout: ActionLayout) -> some View {
        switch layout {
        case .row:
            HStack(spacing: Spacing.small) { buttons }
        case .column:
            VStack(alignment: .leading, spacing: Spacing.small) { buttons }
        }
    }

    private var buttons: some View {
        ForEach(summary.actions) { action in
            Button(action.title, action: action.perform)
                .primaryActionStyle(isPrimary: action.isPrimary, isEnabled: action.isEnabled)
                .fixedSize()
                .help(Self.help(for: action))
                .accessibilityLabel(action.spokenTitle)
                .accessibilityHint(action.unavailableReason ?? "")
                .accessibilityIdentifier(action.id)
        }
    }

    /// The tooltip: why an action is off, else the full title of a short one.
    static func help(for action: FeatureAction) -> String {
        if let reason = action.unavailableReason { return reason }
        return action.spokenTitle == action.title ? "" : action.spokenTitle
    }
}

import JerdDesign
import SwiftUI

/// The dashboard card of one section, from its feature summary. The actions stand in one row.
/// When a narrow card cannot fit them, the next step stays a button and the others move
/// into a More menu, so cards in one row keep one height. A card never drops an action and
/// never truncates a button title.
struct FeatureCard: View {
    /// How the actions stand, in the order the card tries them.
    enum ActionLayout: CaseIterable {
        /// Every action as a button.
        case row
        /// The primary action (else the first) as a button, the others in a More menu.
        case overflow
        /// Every action as a button, one per line, for very narrow cards.
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

    /// Which actions show as buttons and which go into the More menu. Together they are
    /// always every action, in order.
    static func arrangement(
        of actions: [FeatureAction], in layout: ActionLayout
    ) -> (buttons: [FeatureAction], menu: [FeatureAction]) {
        switch layout {
        case .row, .column: return (actions, [])
        case .overflow:
            // The next step stays a button: the primary action, else the first one.
            guard let kept = actions.first(where: \.isPrimary) ?? actions.first else { return ([], []) }
            return ([kept], actions.filter { $0.id != kept.id })
        }
    }

    @ViewBuilder private func actions(in layout: ActionLayout) -> some View {
        let arrangement = Self.arrangement(of: summary.actions, in: layout)
        switch layout {
        case .row, .overflow:
            HStack(spacing: Spacing.small) {
                buttons(arrangement.buttons)
                if !arrangement.menu.isEmpty {
                    moreMenu(arrangement.menu)
                }
            }
        case .column:
            VStack(alignment: .leading, spacing: Spacing.small) { buttons(arrangement.buttons) }
        }
    }

    private func buttons(_ actions: [FeatureAction]) -> some View {
        ForEach(actions) { action in
            Button(action.title, action: action.perform)
                .primaryActionStyle(isPrimary: action.isPrimary, isEnabled: action.isEnabled)
                .fixedSize()
                .accessibilityIdentifier(action.id)
        }
    }

    private func moreMenu(_ actions: [FeatureAction]) -> some View {
        Menu {
            ForEach(actions) { action in
                Button(action.title, action: action.perform)
                    .disabled(!action.isEnabled)
                    .accessibilityIdentifier(action.id)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More \(section.title) actions")
        .accessibilityLabel("More \(section.title) actions")
        .accessibilityIdentifier(AccessibilityIdentifier.make("dashboard", section.title, "more"))
    }
}

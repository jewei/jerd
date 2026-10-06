import JerdDesign
import SwiftUI

/// The dashboard card of one section, from its feature summary. When a narrow card cannot
/// show every action in full, it keeps only the first one; the Open button leads to the rest.
/// A button title is never truncated.
struct FeatureCard: View {
    let section: AppSection
    let summary: FeatureSummary
    let open: @MainActor () -> Void

    var body: some View {
        SummaryCard(
            section.title, systemImage: section.systemImage, tint: section.tint, status: summary.status,
            summary: summary.summary, identifier: AccessibilityIdentifier.make("dashboard", section.title), open: open
        ) {
            ViewThatFits(in: .horizontal) {
                buttons(summary.actions)
                buttons(Array(summary.actions.prefix(1)))
            }
        }
    }

    private func buttons(_ actions: [FeatureAction]) -> some View {
        HStack(spacing: Spacing.small) {
            ForEach(actions) { action in
                Button(action.title, action: action.perform)
                    .primaryActionStyle(isPrimary: action.isPrimary, isEnabled: action.isEnabled)
                    .fixedSize()
                    .accessibilityIdentifier(action.id)
            }
        }
    }
}

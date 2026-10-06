import JerdDesign
import SwiftUI

/// The dashboard card of one section, from its feature summary.
struct FeatureCard: View {
    let section: AppSection
    let summary: FeatureSummary
    let open: @MainActor () -> Void

    var body: some View {
        SummaryCard(
            section.title, systemImage: section.systemImage, tint: section.tint, status: summary.status,
            summary: summary.summary, identifier: AccessibilityIdentifier.make("dashboard", section.title), open: open
        ) {
            ForEach(summary.actions) { action in
                Button(action.title, action: action.perform)
                    .primaryActionStyle(isPrimary: action.isPrimary, isEnabled: action.isEnabled)
                    .accessibilityIdentifier(action.id)
            }
        }
    }
}

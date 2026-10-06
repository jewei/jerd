import JerdDesign

/// The cards of the overview, in section order.
@MainActor
enum DashboardCards {
    static let sections: [AppSection] = [.sites, .databases, .storage, .mail]

    /// The summary of a section: its feature's, or a placeholder while the feature is not built.
    static func summary(for section: AppSection, in state: AppState) -> FeatureSummary {
        state.feature(for: section)?.summary ?? placeholder
    }

    static let placeholder = FeatureSummary(
        status: DisplayStatus("Not available", tone: .idle), summary: PlaceholderPage.message)
}

import JerdDesign

/// What the dashboard card of a feature shows: one status, one summary line, and quick actions.
public struct FeatureSummary {
    public let status: DisplayStatus
    /// One or two short lines, for example "2 registered · 2 enabled".
    public let summary: String
    /// At most one action is primary: the next step.
    public let actions: [FeatureAction]

    public init(status: DisplayStatus, summary: String, actions: [FeatureAction] = []) {
        self.status = status
        self.summary = summary
        self.actions = actions
    }

    /// The same summary with every action off.
    public func disablingActions() -> FeatureSummary {
        FeatureSummary(status: status, summary: summary, actions: actions.map { $0.disabled() })
    }
}

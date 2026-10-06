/// A change that waits for HTTPS approval. Nothing was saved and nothing was stopped.
public struct PendingSiteChange: Sendable {
    /// What the approval sheet shows.
    public let setup: HTTPSSetup
    let request: SiteChangeRequest
    /// The preflight result, reused after approval when nothing changed.
    let prepared: PreparedPlan?
}

/// The result of a change.
public enum SiteChangeResult: Sendable {
    /// Saved (or unchanged) and active. The configuration is the saved one.
    case committed(AppConfiguration)
    /// The change needs HTTPS approval first. Call `approve(_:)` after the user approves.
    case needsApproval(PendingSiteChange)
}

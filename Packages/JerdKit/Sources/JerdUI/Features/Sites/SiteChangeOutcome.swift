import JerdWeb

/// The result of a site change: saved and active, or waiting for HTTPS approval.
public enum SiteChangeOutcome: Equatable, Sendable {
    /// Saved (or unchanged) and active. The value is the saved configuration.
    case committed(AppConfiguration)
    /// Nothing was saved or stopped. The change continues after the user approves.
    case needsApproval(HTTPSApproval)
}

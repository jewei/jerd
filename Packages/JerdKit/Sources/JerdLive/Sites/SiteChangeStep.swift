import JerdWeb

/// The result of one site change, as the live ports keep it: saved, or waiting for approval
/// with the one call that continues it.
package enum SiteChangeStep: Sendable {
    /// Saved (or unchanged) and active.
    case committed(AppConfiguration)
    /// Nothing was saved or stopped. `resume` applies the approved setup and continues the change.
    case needsApproval(HTTPSSetup, resume: @Sendable () async throws -> AppConfiguration)
}

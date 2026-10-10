import Foundation
import JerdWeb

/// The site work that a local tunnel launch needs. `SiteChangeTransaction` is the live type, so
/// the launch waits for a site change and a restart rolls back like one.
package protocol ForwardedHostApplying: Sendable {
    /// Applies the saved forwarded hosts and returns the site as the run serves it, or nil when
    /// the run does not serve it. It restarts the run only when the mapping changed.
    func applyForwardedHosts(servingSite siteID: UUID) async throws -> Site?
}

extension SiteChangeTransaction: ForwardedHostApplying {}

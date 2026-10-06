import Foundation
import JerdWeb

/// The site change transaction calls that the live ports use. `SiteChangeTransaction` is the
/// live type. Every change of sites and of PHP or Caddy records goes through it.
package protocol SiteChangeApplying: Sendable {
    func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeResult
    func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeResult
    func approve(_ pending: PendingSiteChange) async throws -> AppConfiguration
    func requestStop() async
}

extension SiteChangeTransaction: SiteChangeApplying {}

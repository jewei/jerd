import Foundation
import JerdWeb

/// The site change transaction calls that the live ports use. `SiteChangeTransaction` is the
/// live type. Every change of sites and of PHP or Caddy records goes through it.
package protocol SiteChangeApplying: Sendable {
    func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeStep
    func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeStep
    func requestStop() async
}

extension SiteChangeTransaction: SiteChangeApplying {
    package func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeStep {
        let result: SiteChangeResult = try await apply(change, startIfStopped: startIfStopped)
        return step(result)
    }

    package func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeStep {
        let result: SiteChangeResult = try await run(siteIDs)
        return step(result)
    }

    /// A waiting change continues through `approve(_:)` of this transaction.
    private nonisolated func step(_ result: SiteChangeResult) -> SiteChangeStep {
        switch result {
        case .committed(let configuration):
            return .committed(configuration)
        case .needsApproval(let pending):
            return .needsApproval(pending.setup) { try await self.approve(pending) }
        }
    }
}

import Foundation
import JerdFoundation

extension EnvironmentCoordinator {
    /// Applies current tunnel hostnames before a connector can send traffic to an active site.
    public func preparePublicHosts(for siteID: UUID) async throws {
        guard let plan = active?.plan, plan.siteIDs.contains(siteID) else {
            throw JerdError.unavailable("Start the selected site before connecting this tunnel.")
        }
        try await ensure(plan, prepared: nil, ticket: ticket())
    }
}

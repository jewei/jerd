import Foundation
import JerdWeb

/// Every live site change, then a stop of each local tunnel route whose site the run no longer
/// serves under the hostname of its launch. So a renamed, removed, or stopped site never leaves
/// a route that can send public traffic to another site with that name.
///
/// The check runs also after a failed change, because a failure can leave fewer sites running.
package struct RouteGuardedSiteChanges: SiteChangeApplying {
    let changes: any SiteChangeApplying
    let environment: any EnvironmentControlling
    let routes: any LocalRouteStopping

    package init(
        changes: any SiteChangeApplying, environment: any EnvironmentControlling, routes: any LocalRouteStopping
    ) {
        self.changes = changes
        self.environment = environment
        self.routes = routes
    }

    package func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeStep {
        guarded(try await checkingRoutes { try await changes.apply(change, startIfStopped: startIfStopped) })
    }

    package func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeStep {
        guarded(try await checkingRoutes { try await changes.run(siteIDs) })
    }

    package func requestStop() async {
        await changes.requestStop()
        await stopUnservedRoutes()
    }

    /// A change that waits for approval checks the routes when it continues.
    private func guarded(_ step: SiteChangeStep) -> SiteChangeStep {
        guard case .needsApproval(let setup, let resume) = step else { return step }
        return .needsApproval(setup) { try await checkingRoutes(resume) }
    }

    private func checkingRoutes<Value: Sendable>(_ body: () async throws -> Value) async throws -> Value {
        do {
            let value = try await body()
            await stopUnservedRoutes()
            return value
        } catch {
            await stopUnservedRoutes()
            throw error
        }
    }

    private func stopUnservedRoutes() async {
        let sites = await environment.runningPlan()?.sites.map(\.site) ?? []
        await routes.stopRoutesToUnservedSites(Dictionary(sites.map { ($0.id, $0.hostname) }) { first, _ in first })
    }
}

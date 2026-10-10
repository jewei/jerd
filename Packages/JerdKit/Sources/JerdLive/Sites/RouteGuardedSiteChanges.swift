import Foundation
import JerdWeb

/// Every live site change, then a stop of each local tunnel route whose site the run no longer
/// serves under the hostname of its launch. So a renamed, removed, or stopped site never leaves
/// a route that can send public traffic to another site with that name.
///
/// The check runs also after a failed change, because a failure can leave fewer sites running.
/// It uses what the run served when the last change ended, so a change that is refused while a
/// restart runs never sees the moment in which no site is served.
package struct RouteGuardedSiteChanges: SiteChangeApplying {
    let changes: any SiteChangeApplying
    let served: any ServedSitesReading
    let routes: any LocalRouteStopping

    package init(changes: any SiteChangeApplying, served: any ServedSitesReading, routes: any LocalRouteStopping) {
        self.changes = changes
        self.served = served
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

    /// Runs `body`, then checks the routes, also when `body` throws.
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
        await routes.stopRoutesToUnservedSites(await served.servedHostnames)
    }
}

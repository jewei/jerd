import Foundation
import JerdFoundation
import JerdWeb
import Testing

@testable import JerdLive

@Suite struct RouteGuardedSiteChangesTests {
    private let site = SampleWeb.site()

    private struct Guard {
        let transaction = RecordingSiteTransaction()
        let environment = FakeEnvironment()
        let routes = RecordingRouteStopper()
        var changes: RouteGuardedSiteChanges {
            RouteGuardedSiteChanges(changes: transaction, environment: environment, routes: routes)
        }
    }

    private func plan(_ sites: [Site]) -> ServingPlan {
        ServingPlan(sites: sites.map { PlannedSite(site: $0, runtime: SampleWeb.php()) }, caddy: SampleWeb.caddy())
    }

    @Test func aCommittedChangeChecksTheRoutesWithTheServedHostnames() async throws {
        let fixture = Guard()
        await fixture.environment.setRunning(plan([site]))
        _ = try await fixture.changes.apply(.enabled(site.id, true), startIfStopped: false)
        _ = try await fixture.changes.run([site.id])
        #expect(await fixture.routes.checks == [[site.id: "shop.test"], [site.id: "shop.test"]])
    }

    /// A failed change can leave fewer sites running, so the routes are checked also then.
    @Test func aFailedChangeChecksTheRoutesToo() async throws {
        let fixture = Guard()
        let failing = FailingSiteChanges()
        let changes = RouteGuardedSiteChanges(
            changes: failing, environment: fixture.environment, routes: fixture.routes)
        await #expect(throws: FailingSiteChanges.failure) {
            try await changes.run([site.id])
        }
        #expect(await fixture.routes.checks == [[:]])
    }

    @Test func aChangeThatWaitsForApprovalChecksTheRoutesWhenItContinues() async throws {
        let fixture = Guard()
        let approved = AppConfiguration()
        await fixture.transaction.enqueue(.needsApproval(try SampleWeb.setup(hostnames: ["shop.test"])) { approved })
        let step = try await fixture.changes.apply(.enabled(site.id, true), startIfStopped: true)
        guard case .needsApproval(_, let resume) = step else {
            Issue.record("Expected an approval")
            return
        }
        #expect(await fixture.routes.checks.count == 1)
        await fixture.environment.setRunning(plan([site]))
        #expect(try await resume() == approved)
        #expect(await fixture.routes.checks.last == [site.id: "shop.test"])
    }

    /// After the app's Stop no site runs, so every local route to a site stops.
    @Test func theAppsStopChecksTheRoutesAfterTheRunStopped() async {
        let fixture = Guard()
        await fixture.environment.setRunning(plan([site]))
        let changes = RouteGuardedSiteChanges(
            changes: StoppingSiteChanges(environment: fixture.environment), environment: fixture.environment,
            routes: fixture.routes)
        await changes.requestStop()
        #expect(await fixture.routes.checks == [[:]])
    }
}

/// Site changes that always fail, for the guard's failure path.
private struct FailingSiteChanges: SiteChangeApplying {
    static let failure = JerdError.processFailed("The site change failed.")

    func apply(_ change: SiteChange, startIfStopped: Bool) throws -> SiteChangeStep { throw Self.failure }
    func run(_ siteIDs: Set<UUID>) throws -> SiteChangeStep { throw Self.failure }
    func requestStop() {}
}

/// Site changes whose Stop stops the environment, as the live transaction does.
private struct StoppingSiteChanges: SiteChangeApplying {
    let environment: FakeEnvironment

    func apply(_ change: SiteChange, startIfStopped: Bool) -> SiteChangeStep { .committed(AppConfiguration()) }
    func run(_ siteIDs: Set<UUID>) -> SiteChangeStep { .committed(AppConfiguration()) }
    func requestStop() async { await environment.stop() }
}

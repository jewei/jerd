import Foundation
import JerdFoundation
import JerdWeb
import Testing

@testable import JerdLive

@Suite struct RouteGuardedSiteChangesTests {
    private let site = SampleWeb.site()

    private struct Guard {
        let transaction = RecordingSiteTransaction()
        let served = FakeServedSites()
        let routes = RecordingRouteStopper()

        func changes(_ inner: (any SiteChangeApplying)? = nil) -> RouteGuardedSiteChanges {
            RouteGuardedSiteChanges(changes: inner ?? transaction, served: served, routes: routes)
        }
    }

    @Test func aCommittedChangeChecksTheRoutesWithTheServedHostnames() async throws {
        let fixture = Guard()
        await fixture.served.set([site.id: "shop.test"])
        _ = try await fixture.changes().apply(.enabled(site.id, true), startIfStopped: false)
        _ = try await fixture.changes().run([site.id])
        #expect(await fixture.routes.checks == [[site.id: "shop.test"], [site.id: "shop.test"]])
    }

    /// A failed change can leave fewer sites running, so the routes are checked also then.
    @Test func aFailedChangeChecksTheRoutesToo() async throws {
        let fixture = Guard()
        let changes = fixture.changes(FailingSiteChanges())
        await #expect(throws: FailingSiteChanges.failure) {
            try await changes.run([site.id])
        }
        #expect(await fixture.routes.checks == [[:]])
    }

    @Test func aChangeThatWaitsForApprovalChecksTheRoutesWhenItContinues() async throws {
        let fixture = Guard()
        let approved = AppConfiguration()
        await fixture.transaction.enqueue(.needsApproval(try SampleWeb.setup(hostnames: ["shop.test"])) { approved })
        let step = try await fixture.changes().apply(.enabled(site.id, true), startIfStopped: true)
        guard case .needsApproval(_, let resume) = step else {
            Issue.record("Expected an approval")
            return
        }
        #expect(await fixture.routes.checks.count == 1)
        await fixture.served.set([site.id: "shop.test"])
        #expect(try await resume() == approved)
        #expect(await fixture.routes.checks.last == [site.id: "shop.test"])
    }

    /// The check reads the served sites after the Stop, so every route to a site stops.
    @Test func theAppsStopChecksTheRoutesAfterItEnds() async {
        let fixture = Guard()
        await fixture.served.set([site.id: "shop.test"])
        await fixture.changes(StoppingSiteChanges(served: fixture.served)).requestStop()
        #expect(await fixture.routes.checks == [[:]])
    }
}

/// What the run served when the last change ended, as a test sets it.
private actor FakeServedSites: ServedSitesReading {
    private(set) var servedHostnames: [UUID: String] = [:]

    func set(_ hostnames: [UUID: String]) { servedHostnames = hostnames }
}

/// Site changes that always fail, for the guard's failure path.
private struct FailingSiteChanges: SiteChangeApplying {
    static let failure = JerdError.processFailed("The site change failed.")

    func apply(_ change: SiteChange, startIfStopped: Bool) throws -> SiteChangeStep { throw Self.failure }
    func run(_ siteIDs: Set<UUID>) throws -> SiteChangeStep { throw Self.failure }
    func requestStop() {}
}

/// Site changes whose Stop ends every served site, as the live transaction does.
private struct StoppingSiteChanges: SiteChangeApplying {
    let served: FakeServedSites

    func apply(_ change: SiteChange, startIfStopped: Bool) -> SiteChangeStep { .committed(AppConfiguration()) }
    func run(_ siteIDs: Set<UUID>) -> SiteChangeStep { .committed(AppConfiguration()) }
    func requestStop() async { await served.set([:]) }
}

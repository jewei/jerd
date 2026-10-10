import Foundation
import JerdFoundation
import JerdTunnels
import Testing

/// A local route keeps the `.test` name of its launch, so Jerd stops it when the web run no
/// longer serves its site under that name. Otherwise public traffic could reach another site.
@Suite(.timeLimit(.minutes(1))) struct TunnelSupervisorSiteRouteTests {
    private let siteID = UUID()

    /// A connected tunnel with a Jerd route to `siteID`, which resolved to `shop.test`.
    private func connectedSiteRoute() async throws -> SupervisorFixture {
        let fixture = try await SupervisorFixture()
        var local = fixture.registration
        local.routing = .local
        local.siteID = siteID
        try await fixture.supervisor.save(local)
        try await fixture.startAndSettle()
        return fixture
    }

    @Test(arguments: [[], ["renamed.test"]] as [[String]])
    func aRouteToASiteThatStoppedOrChangedItsNameStopsWithItsReason(_ names: [String]) async throws {
        let fixture = try await connectedSiteRoute()
        defer { fixture.folder.remove() }
        let served = Dictionary(uniqueKeysWithValues: names.map { (siteID, $0) })
        await fixture.supervisor.stopRoutesToUnservedSites(served)
        #expect(await fixture.state() == .failed(TunnelMessage.siteRouteStopped))
        #expect(await fixture.connector.disconnects.count == 1)
        #expect(await fixture.connector.owned.isEmpty)
    }

    @Test func aRouteToASiteThatTheRunStillServesKeepsRunning() async throws {
        let fixture = try await connectedSiteRoute()
        defer { fixture.folder.remove() }
        await fixture.supervisor.stopRoutesToUnservedSites([siteID: "shop.test", UUID(): "other.test"])
        #expect(await fixture.state()?.isActive == true)
        #expect(await fixture.connector.disconnects.isEmpty)
        try await fixture.supervisor.stop(id: fixture.id)
    }

    /// A route from the Cloudflare dashboard, or to an address, does not name a Jerd site.
    @Test func otherRoutesNeverStopForASiteChange() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        var reference = fixture.registration
        reference.siteID = siteID
        try await fixture.supervisor.save(reference)
        try await fixture.startAndSettle()
        await fixture.supervisor.stopRoutesToUnservedSites([:])
        #expect(await fixture.state()?.isActive == true)
        #expect(await fixture.connector.disconnects.isEmpty)
        try await fixture.supervisor.stop(id: fixture.id)
    }

    /// After the stop, the user can connect again at once.
    @Test func aStoppedRouteCanConnectAgain() async throws {
        let fixture = try await connectedSiteRoute()
        defer { fixture.folder.remove() }
        await fixture.supervisor.stopRoutesToUnservedSites([:])
        try await fixture.startAndSettle()
        #expect(await fixture.state()?.isActive == true)
        try await fixture.supervisor.stop(id: fixture.id)
    }

    /// An earlier build could save "Connect when Jerd opens" for a Jerd route to a site. No site
    /// runs at launch, so that tunnel waits for the user instead of failing at every launch.
    @Test func aJerdRouteToASiteNeverConnectsAtLaunch() async throws {
        let fixture = try await SupervisorFixture(startOnLaunch: true)
        defer { fixture.folder.remove() }
        var local = fixture.registration
        local.routing = .local
        local.siteID = siteID
        try await fixture.supervisor.save(local)
        #expect(try await fixture.supervisor.connectStartupTunnels().isEmpty)
        #expect(await fixture.connector.launches.isEmpty)
        #expect(await fixture.state() == .stopped)
    }

    /// A launch that has no connector yet when the site stops would otherwise start with a name
    /// that no site serves, and no later check would see it.
    @Test func aLaunchInProgressToASiteThatIsGoneStops() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        var local = fixture.registration
        local.routing = .local
        local.siteID = siteID
        try await fixture.supervisor.save(local)
        await fixture.connector.hold("connect")
        let starting = Task { try await fixture.supervisor.start(id: fixture.id) }
        await fixture.connector.waitForHeld("connect", count: 1)
        let checking = Task { await fixture.supervisor.stopRoutesToUnservedSites([:]) }
        await fixture.reach(.stopping)
        await fixture.connector.release("connect")
        await checking.value
        _ = await starting.result
        #expect(await fixture.state() == .failed(TunnelMessage.siteRouteStopped))
        #expect(await fixture.connector.owned.isEmpty)
    }

    /// The name of a launch in progress is not known yet; it resolves the site as the run
    /// serves it now, so a served site keeps the launch.
    @Test func aLaunchInProgressToAServedSiteContinues() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        var local = fixture.registration
        local.routing = .local
        local.siteID = siteID
        try await fixture.supervisor.save(local)
        await fixture.connector.hold("connect")
        let starting = Task { try await fixture.supervisor.start(id: fixture.id) }
        await fixture.connector.waitForHeld("connect", count: 1)
        await fixture.supervisor.stopRoutesToUnservedSites([siteID: "renamed.test"])
        await fixture.connector.release("connect")
        try await starting.value
        #expect(await fixture.state()?.isActive == true)
        try await fixture.supervisor.stop(id: fixture.id)
    }
}

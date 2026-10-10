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
}

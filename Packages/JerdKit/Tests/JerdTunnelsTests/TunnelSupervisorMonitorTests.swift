import Foundation
import JerdFoundation
import JerdProcess
import JerdTunnels
import Testing

@Suite(.timeLimit(.minutes(1))) struct TunnelSupervisorMonitorTests {
    @Test func theLaunchPassesTheSavedTokenAndRuntime() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        let launch = try #require(await fixture.connector.launches.first)
        #expect(launch.token == (try TunnelToken(TokenSamples.valid)))
        #expect(launch.runtime.id == "cloudflared-2026.9.3")
        #expect(launch.registration == fixture.registration)
        #expect(await fixture.processID() == 30_000)
        try await fixture.supervisor.stopAll()
    }

    /// Regression test: the first connection is "Connecting…", a lost one "Reconnecting…".
    @Test func connectedRequiresReadinessOfTheOwnedConnector() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        #expect(await fixture.state() == .connecting)
        await fixture.connector.setReadiness(.ready)
        fixture.clock.advance(by: .seconds(5))
        await fixture.reach(.connected)
        await fixture.connector.setReadiness(.waiting)
        await fixture.clock.waitForSleeper(.seconds(5))
        fixture.clock.advance(by: .seconds(5))
        await fixture.reach(.reconnecting)
        try await fixture.supervisor.stopAll()
        #expect(await fixture.state() == .stopped)
    }

    @Test func anUnexpectedExitRestartsAfterTheBackoffDelay() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.clock.waitForSleeper(.seconds(2))
        #expect(await fixture.connector.disconnects.count == 1)
        #expect(await fixture.processID() == nil)
        #expect(await fixture.state() == .connecting)
        fixture.clock.advance(by: .seconds(2))
        await fixture.connector.waitForLaunches(2)
        await fixture.clock.waitForSleeper(.seconds(5))
        #expect(await fixture.processID() == 30_001)
        try await fixture.supervisor.stopAll()
    }

    @Test func stopDuringTheBackoffPreventsTheNextLaunch() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.clock.waitForSleeper(.seconds(2))
        try await fixture.supervisor.stop(id: fixture.id)
        #expect(fixture.clock.pendingDelays.isEmpty)
        fixture.clock.advance(by: .seconds(60))
        #expect(await fixture.connector.launches.count == 1)
        #expect(await fixture.state() == .stopped)
    }

    @Test func anExitWithoutRestartNeedsTheUser() async throws {
        let fixture = try await SupervisorFixture(restartOnFailure: false)
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.reach(.failed(TunnelMessage.processExited))
        #expect(fixture.clock.pendingDelays.isEmpty)
        #expect(await fixture.connector.launches.count == 1)
        #expect(await fixture.processID() == nil)
    }

    @Test func aRejectedTokenStopsTheConnectorWithoutARetry() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.setOutputAtLaunch("2026-09-03T10:15:42Z ERR Provided Tunnel token is not valid.\n")
        try await fixture.supervisor.start(id: fixture.id)
        await fixture.reach(.failed(TunnelMessage.tokenRejected))
        await fixture.until { $0.processID == nil }
        #expect(await fixture.connector.disconnects.count == 1)
        #expect(fixture.clock.pendingDelays.isEmpty)
        #expect(await fixture.connector.launches.count == 1)
    }

    /// Regression test at the supervisor level: an origin 401 line keeps the connector running.
    @Test func anOriginAuthorizationErrorDoesNotStopTheConnector() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.setOutputAtLaunch(
            "2026-09-03T10:15:42Z ERR  error=\"Unauthorized\" originService=http://127.0.0.1:8000\n")
        try await fixture.startAndSettle()
        #expect(await fixture.state() == .connecting)
        #expect(await fixture.connector.disconnects.isEmpty)
        try await fixture.supervisor.stopAll()
    }

    /// Regression test: a retry that meets a permanent error shows the cause and stops retrying.
    @Test func aRetryThatMeetsAPermanentErrorShowsTheCause() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.secrets.set(nil, id: fixture.id)
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.clock.waitForSleeper(.seconds(2))
        fixture.clock.advance(by: .seconds(2))
        await fixture.reach(.failed(TunnelMessage.tokenMissing))
        #expect(fixture.clock.pendingDelays.isEmpty)
        #expect(await fixture.connector.launches.count == 1)
    }

    @Test func aRetryThatTimesOutTriesAgainWithALongerDelay() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.setConnectFailure(JerdError.timedOut("Command timed out."))
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.clock.waitForSleeper(.seconds(2))
        fixture.clock.advance(by: .seconds(2))
        await fixture.clock.waitForSleeper(.seconds(5))
        #expect(await fixture.state() == .connecting)
        #expect(await fixture.connector.launches.count == 2)
        try await fixture.supervisor.stop(id: fixture.id)
    }

    @Test func aFirstLaunchFailureIsShownThrownAndRedacted() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.setConnectFailure(JerdError.processFailed("cloudflared said \(TokenSamples.secret)"))
        let message = "cloudflared said \(LogRedactor.marker)"
        await #expect(throws: JerdError.processFailed(message)) { try await fixture.supervisor.start(id: fixture.id) }
        #expect(await fixture.state() == .failed(message))
        #expect(fixture.clock.pendingDelays.isEmpty)
        await fixture.connector.setConnectFailure(nil)
        try await fixture.startAndSettle()
        try await fixture.supervisor.stopAll()
    }

    @Test func anUnexpectedListenerStopsTheOwnedConnector() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.setReadiness(.unexpectedListener)
        try await fixture.supervisor.start(id: fixture.id)
        await fixture.reach(.failed(TunnelMessage.unexpectedListener))
        await fixture.connector.waitForDisconnects(1)
        await fixture.until { $0.processID == nil }
        #expect(await fixture.connector.launches.count == 1)
    }

    /// Regression test: startup errors overwrote each other and only the last was shown.
    @Test func startupConnectsOnlyMarkedTunnelsAndReportsEveryFailure() async throws {
        let fixture = try await SupervisorFixture(startOnLaunch: true)
        defer { fixture.folder.remove() }
        var second = try await fixture.addSecond()
        second.startOnLaunch = true
        try await fixture.supervisor.save(second)
        let third = TunnelRegistration(name: "Third", hostname: "three.example.com", metricsPort: 20_243)
        try await fixture.supervisor.save(
            third, token: TokenSamples.token(account: "a", tunnel: UUID().uuidString, secret: "s"))
        await fixture.secrets.set(nil, id: fixture.id)
        await fixture.connector.setConnectFailure(
            JerdError.unavailable("Local port 20242 is occupied. No process was stopped."))
        let failures = try await fixture.supervisor.connectStartupTunnels()
        #expect(
            failures == [
                TunnelStartupFailure(id: fixture.id, name: "Preview", message: TunnelMessage.tokenMissing),
                TunnelStartupFailure(
                    id: second.id, name: "Second", message: "Local port 20242 is occupied. No process was stopped."),
            ])
        #expect(await fixture.state(third.id) == .stopped)
    }
}

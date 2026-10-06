import Foundation
import JerdFoundation
import JerdTunnels
import Testing

/// Fix of review tunnels-r1 H-1: a tunnel that failed by itself kept its finished monitor in the
/// work slot, so Connect, Edit, Remove, and a runtime change were refused until the user selected
/// Stop. Each terminal failure must now leave the tunnel free at once.
@Suite(.timeLimit(.minutes(1))) struct TunnelSupervisorRecoveryTests {
    private static let rejection = "2026-09-03T10:15:42Z ERR Provided Tunnel token is not valid.\n"

    @Test func aRejectedTokenNeedsNoStopBeforeTheEdit() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.setOutputAtLaunch(Self.rejection)
        try await fixture.supervisor.start(id: fixture.id)
        await fixture.settle(.failed(TunnelMessage.tokenRejected))
        try await fixture.expectNoStopNeeded()
    }

    @Test func anExitWithoutRestartNeedsNoStopBeforeConnect() async throws {
        let fixture = try await SupervisorFixture(restartOnFailure: false)
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.settle(.failed(TunnelMessage.processExited))
        try await fixture.expectNoStopNeeded()
    }

    @Test func anUnexpectedListenerNeedsNoStopAfterTheGracefulStop() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.setReadiness(.unexpectedListener)
        try await fixture.supervisor.start(id: fixture.id)
        await fixture.settle(.failed(TunnelMessage.unexpectedListener))
        try await fixture.expectNoStopNeeded()
    }

    @Test func aRetryThatMeetsAMissingTokenNeedsNoStopBeforeTheEdit() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.secrets.set(nil, id: fixture.id)
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.clock.waitForSleeper(.seconds(2))
        fixture.clock.advance(by: .seconds(2))
        await fixture.settle(.failed(TunnelMessage.tokenMissing))
        try await fixture.expectNoStopNeeded()
    }

    /// Fix of review tunnels-r1 L-1: the rejection is only in the last output, which reaches the log
    /// when Jerd collects the exited connector. The retries must stop.
    @Test func aRejectionInTheLateOutputOfAnExitedConnectorStopsTheRetries() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.exit(fixture.id, lateOutput: Self.rejection)
        fixture.clock.advance(by: .seconds(5))
        await fixture.settle(.failed(TunnelMessage.tokenRejected))
        #expect(fixture.clock.pendingDelays.isEmpty)
        #expect(await fixture.connector.launches.count == 1)
        #expect(await fixture.connector.disconnects.count == 1)
        try await fixture.expectNoStopNeeded()
    }

    /// Fix of review tunnels-r1 L-2 at the supervisor level: five quick exits in a row end the retries.
    @Test func aConnectorThatExitsAfterEachStartStopsAfterFiveStarts() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        for delay in [2, 5, 15, 30] {
            await fixture.connector.exit(fixture.id)
            fixture.clock.advance(by: .seconds(5))
            await fixture.clock.waitForSleeper(.seconds(delay))
            fixture.clock.advance(by: .seconds(delay))
            await fixture.clock.waitForSleeper(.seconds(5))
        }
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.settle(.failed(TunnelMessage.failedStarts(5, lastError: nil)))
        #expect(fixture.clock.pendingDelays.isEmpty)
        #expect(await fixture.connector.launches.count == 5)
        try await fixture.expectNoStopNeeded()
    }

    /// A connector that Jerd could not stop stays owned, so it still blocks every change until Stop.
    @Test func aConnectorThatCouldNotBeCollectedStillNeedsStop() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.setDisconnectFailure(.processFailed(TunnelMessage.notStopped))
        await fixture.connector.exit(fixture.id)
        fixture.clock.advance(by: .seconds(5))
        await fixture.reach(.failed(TunnelMessage.notStopped))
        #expect(await fixture.processID() == 30_000)
        await #expect(throws: JerdError.unavailable(TunnelMessage.alreadyActive)) {
            try await fixture.supervisor.start(id: fixture.id)
        }
        await #expect(throws: JerdError.unavailable(TunnelMessage.stopBeforeEdit)) {
            try await fixture.supervisor.save(fixture.registration, token: TokenSamples.rotated)
        }
        await #expect(throws: JerdError.unavailable(TunnelMessage.stopBeforeRemove)) {
            try await fixture.supervisor.remove(id: fixture.id)
        }
        await #expect(throws: JerdError.unavailable(TunnelMessage.runtimeInUse)) {
            try await fixture.supervisor.useRuntime(at: URL(fileURLWithPath: "/runtimes/new/cloudflared"))
        }
        await fixture.connector.setDisconnectFailure(nil)
        try await fixture.supervisor.stop(id: fixture.id)
        try await fixture.expectNoStopNeeded()
    }

    @Test func snapshotUpdatesStartWithTheCurrentStateAndKeepTheNewest() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        var updates = await fixture.supervisor.snapshotUpdates().makeAsyncIterator()
        #expect(await updates.next()?.first?.state == .stopped)
        try await fixture.startAndSettle()
        let newest = await updates.next()?.first
        #expect(newest?.state == .connecting)
        #expect(newest?.processID == 30_000)
        try await fixture.supervisor.stop(id: fixture.id)
        #expect(await updates.next()?.first?.state == .stopped)
    }
}

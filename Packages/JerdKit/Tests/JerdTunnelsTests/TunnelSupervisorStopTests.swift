import Foundation
import JerdFoundation
import JerdTunnels
import Testing

@Suite(.timeLimit(.minutes(1))) struct TunnelSupervisorStopTests {
    @Test func stopDuringAnInFlightLaunchLeavesNoProcess() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.hold("connect")
        let starting = Task { try await fixture.supervisor.start(id: fixture.id) }
        await fixture.connector.waitForHeld("connect", count: 1)
        let stopping = Task { try await fixture.supervisor.stop(id: fixture.id) }
        await fixture.reach(.stopping)
        await fixture.connector.release("connect")
        await #expect(throws: JerdError.unavailable(TunnelMessage.cancelled)) { try await starting.value }
        try await stopping.value
        #expect(await fixture.connector.owned.isEmpty)
        #expect(await fixture.connector.disconnects.count == 1)
        #expect(await fixture.state() == .stopped)
        #expect(fixture.clock.pendingDelays.isEmpty)
    }

    /// A Stop during a launch, then a new Connect that is also stopped during its launch: each Stop
    /// reaches its own launch. The slot rule itself (spec E 7.1.1) is proved by `TunnelWorkSlotsTests`,
    /// because the actor cannot be made to resume the late launch after the newer Connect.
    @Test func eachStopReachesTheLaunchOfItsOwnConnect() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.hold("connect")
        let first = Task { try await fixture.supervisor.start(id: fixture.id) }
        await fixture.connector.waitForHeld("connect", count: 1)
        let stopping = Task { try await fixture.supervisor.stop(id: fixture.id) }
        await fixture.reach(.stopping)
        await fixture.connector.hold("connect")
        await fixture.connector.release("connect")
        try await stopping.value
        let second = Task { try await fixture.supervisor.start(id: fixture.id) }
        await fixture.connector.waitForHeld("connect", count: 1)
        _ = await first.result
        let stoppingSecond = Task { try await fixture.supervisor.stop(id: fixture.id) }
        await fixture.reach(.stopping)
        await fixture.connector.release("connect")
        await #expect(throws: JerdError.unavailable(TunnelMessage.cancelled)) { try await second.value }
        try await stoppingSecond.value
        #expect(await fixture.connector.owned.isEmpty)
        #expect(await fixture.connector.disconnects.count == 2)
        #expect(await fixture.state() == .stopped)
        #expect(fixture.clock.pendingDelays.isEmpty)
    }

    @Test func concurrentStopsShareOneOperationBeforeANewConnect() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.hold("disconnect")
        let first = Task { try await fixture.supervisor.stop(id: fixture.id) }
        await fixture.connector.waitForHeld("disconnect", count: 1)
        let second = Task { try await fixture.supervisor.stop(id: fixture.id) }
        await #expect(throws: JerdError.unavailable(TunnelMessage.alreadyActive)) {
            try await fixture.supervisor.start(id: fixture.id)
        }
        await fixture.connector.release("disconnect")
        try await first.value
        try await second.value
        #expect(await fixture.connector.disconnects.count == 1)
        try await fixture.startAndSettle()
        #expect(await fixture.connector.owned.count == 1)
        try await fixture.supervisor.stopAll()
    }

    @Test func aFailedGracefulStopKeepsOwnershipAndTheTokenAndCancelsQuit() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try await fixture.startAndSettle()
        await fixture.connector.setDisconnectFailure(.processFailed(TunnelMessage.notStopped))
        await #expect(throws: JerdError.processFailed(TunnelMessage.notStopped)) {
            try await fixture.supervisor.stop(id: fixture.id)
        }
        #expect(await fixture.state() == .failed(TunnelMessage.notStopped))
        #expect(await fixture.processID() == 30_000)
        #expect(await fixture.secrets.values[fixture.id] == TokenSamples.valid)
        await #expect(throws: JerdError.unavailable(TunnelMessage.stopBeforeRemove)) {
            try await fixture.supervisor.remove(id: fixture.id)
        }
        await #expect(throws: JerdError.processFailed(TunnelMessage.notStopped)) {
            try await fixture.supervisor.stopAll()
        }
        await fixture.connector.setDisconnectFailure(nil)
        try await fixture.supervisor.stop(id: fixture.id)
        try await fixture.supervisor.remove(id: fixture.id)
        #expect(await fixture.secrets.values[fixture.id] == nil)
    }

    /// A readiness result that arrives after Stop cannot stop or relabel the replacement connector.
    @Test func aStaleReadinessResultCannotAffectAReplacementConnector() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        await fixture.connector.hold("readiness")
        await fixture.connector.setHeldReadinessResult(.unexpectedListener)
        try await fixture.supervisor.start(id: fixture.id)
        await fixture.connector.waitForHeld("readiness", count: 1)
        let stopping = Task { try await fixture.supervisor.stop(id: fixture.id) }
        await fixture.reach(.stopping)
        await #expect(throws: JerdError.unavailable(TunnelMessage.alreadyActive)) {
            try await fixture.supervisor.start(id: fixture.id)
        }
        await fixture.connector.release("readiness")
        try await stopping.value
        #expect(await fixture.state() == .stopped)
        await fixture.connector.setReadiness(.ready)
        try await fixture.supervisor.start(id: fixture.id)
        await fixture.reach(.connected)
        #expect(await fixture.connector.disconnects.count == 1)
        #expect(await fixture.processID() == 30_001)
        try await fixture.supervisor.stopAll()
    }

    @Test func tunnelsRunIndependentlyAndKeepTheirTokensAfterStop() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        let second = try await fixture.addSecond()
        try await fixture.supervisor.start(id: fixture.id)
        try await fixture.supervisor.start(id: second.id)
        try await fixture.supervisor.stop(id: fixture.id)
        #expect(await fixture.connector.owned.keys.sorted { $0.uuidString < $1.uuidString } == [second.id])
        #expect(await fixture.processID(second.id) != nil)
        #expect(await fixture.secrets.values[fixture.id] == TokenSamples.valid)
        try await fixture.supervisor.stopAll()
        try await fixture.supervisor.start(id: fixture.id)
        try await fixture.supervisor.stopAll()
        #expect(await fixture.connector.owned.isEmpty)
        #expect(await fixture.secrets.values.count == 2)
    }

    /// Fix of spec E 7.3.4: Quit stopped tunnels one after another, up to 30 s each.
    @Test func stopAllStopsEveryConnectorAtTheSameTime() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        let second = try await fixture.addSecond()
        try await fixture.supervisor.start(id: fixture.id)
        try await fixture.supervisor.start(id: second.id)
        await fixture.connector.hold("disconnect", count: 2)
        let quitting = Task { try await fixture.supervisor.stopAll() }
        await fixture.connector.waitForHeld("disconnect", count: 2)
        await #expect(throws: JerdError.unavailable(TunnelMessage.busy)) {
            try await fixture.supervisor.start(id: fixture.id)
        }
        await fixture.connector.release("disconnect")
        try await quitting.value
        #expect(await fixture.connector.owned.isEmpty)
        #expect(await fixture.state() == .stopped)
        #expect(await fixture.state(second.id) == .stopped)
    }
}

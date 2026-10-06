import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct EnvironmentCoordinatorStopTests {
    @Test func aStopDuringListenerAcquisitionPreventsTheEngineStart() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        await harness.system.pauseNextAcquire()
        let plan = harness.plan([try harness.site("demo.test")])
        let ensure = Task { try await harness.ensure(plan) }
        #expect(await waitUntil { await harness.system.isPausedInAcquire })
        await harness.coordinator.requestStop()
        await harness.system.resume()
        await #expect(throws: CancellationError.self) { try await ensure.value }
        #expect(await harness.engine.starts == 0)
        #expect(await harness.system.released == 1)
        #expect(await harness.coordinator.snapshot().state == .stopped)
    }

    /// The old code reset a Bool on entry, so a Stop just before an activation was lost.
    @Test func aStopBeforeTheNextStepOfAnOperationIsNeverLost() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let plan = harness.plan([try harness.site("demo.test")])
        let ticket = await harness.coordinator.ticket()
        await harness.coordinator.requestStop()
        #expect(await harness.coordinator.isStopRequested(since: ticket))
        await #expect(throws: CancellationError.self) {
            try await harness.coordinator.preflight(plan, ticket: ticket)
        }
        await #expect(throws: CancellationError.self) {
            try await harness.coordinator.ensure(plan, prepared: nil, ticket: ticket)
        }
        #expect(await harness.engine.starts == 0)
        try await harness.ensure(plan)
        #expect(await harness.engine.starts == 1)
    }

    @Test func aStopWaitsForTheRunningOperationAndEndsStopped() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        await harness.system.pauseNextAcquire()
        let ensure = Task { try await harness.ensure(harness.plan([try harness.site("demo.test")])) }
        #expect(await waitUntil { await harness.system.isPausedInAcquire })
        let stop = Task { await harness.coordinator.stop() }
        await harness.system.resume()
        await stop.value
        await #expect(throws: CancellationError.self) { try await ensure.value }
        #expect(await harness.coordinator.snapshot().state == .stopped)
    }

    @Test func aSecondOperationDuringAnotherIsRefused() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        await harness.system.pauseNextAcquire()
        let plan = harness.plan([try harness.site("demo.test")])
        let ensure = Task { try await harness.ensure(plan) }
        #expect(await waitUntil { await harness.system.isPausedInAcquire })
        await #expect(throws: JerdError.unavailable("Wait for the current environment operation.")) {
            try await harness.ensure(plan)
        }
        await harness.system.resume()
        try await ensure.value
        await harness.coordinator.stop()
    }

    @Test func haltStopsTheRunWithoutCancellingLaterSteps() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let plan = harness.plan([try harness.site("demo.test")])
        let ticket = await harness.coordinator.ticket()
        try await harness.coordinator.ensure(plan, prepared: nil, ticket: ticket)
        await harness.coordinator.halt()
        #expect(await !harness.coordinator.isStopRequested(since: ticket))
        try await harness.coordinator.ensure(plan, prepared: nil, ticket: ticket)
        #expect(await harness.engine.starts == 2)
        await harness.coordinator.markSetupRemoved()
        #expect(await harness.coordinator.snapshot().state == .setupRequired)
    }
}

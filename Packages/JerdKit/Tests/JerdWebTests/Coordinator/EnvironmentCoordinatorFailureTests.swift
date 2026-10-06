import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

/// An engine failure while an operation holds the gate is never lost.
///
/// Each test holds the fake engine inside an operation, crashes the run, and waits until the
/// coordinator has recorded the failure. Only then does the operation continue, so the failure
/// always arrives while the gate is busy.
@Suite struct EnvironmentCoordinatorFailureTests {
    @Test func aFailureDuringAPreflightEndsTheRunWhenThePreflightEnds() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let coordinator = harness.coordinator
        let plan = harness.plan([try harness.site("demo.test")])
        try await harness.ensure(plan)
        await harness.engine.holdNextPreflight()
        let preflight = Task { try await coordinator.preflight(plan, ticket: await coordinator.ticket()) }
        #expect(await waitUntil { await harness.engine.isHolding })
        await harness.engine.crash()
        #expect(await waitUntil { await coordinator.pendingFailure != nil })
        #expect(await coordinator.snapshot().state == .running)
        await harness.engine.resumeHeld()
        _ = try await preflight.value
        #expect(await coordinator.snapshot() == EnvironmentSnapshot(state: .failed("test exit"), siteIDs: []))
        #expect(await coordinator.runningPlan() == nil)
        #expect(await harness.system.released == 1)
        try await harness.ensure(plan)
        #expect(await coordinator.snapshot().state == .running)
        #expect(await harness.engine.starts == 2)
    }

    @Test func aFailureDuringAnEnsureThatKeepsTheRunEndsTheRunWhenTheEnsureEnds() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let coordinator = harness.coordinator
        let plan = harness.plan([try harness.site("demo.test")])
        try await harness.ensure(plan)
        await harness.engine.holdNextHealthCheck()
        let ensure = Task { try await harness.ensure(plan) }
        #expect(await waitUntil { await harness.engine.isHolding })
        await harness.engine.crash()
        #expect(await waitUntil { await coordinator.pendingFailure != nil })
        await harness.engine.resumeHeld()
        try await ensure.value
        #expect(await harness.engine.starts == 1)
        #expect(await coordinator.snapshot() == EnvironmentSnapshot(state: .failed("test exit"), siteIDs: []))
        #expect(await harness.system.released == 1)
    }

    @Test func aKnownFailureIsNeverKeptByTheNextEnsure() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let coordinator = harness.coordinator
        let plan = harness.plan([try harness.site("demo.test")])
        try await harness.ensure(plan)
        await harness.engine.holdNextPreflight()
        let preflight = Task { try await coordinator.preflight(plan, ticket: await coordinator.ticket()) }
        #expect(await waitUntil { await harness.engine.isHolding })
        await harness.engine.crash()
        #expect(await waitUntil { await coordinator.pendingFailure != nil })
        await harness.engine.resumeHeld()
        let prepared = try await preflight.value
        try await harness.ensure(plan, prepared: prepared)
        #expect(await harness.engine.starts == 2)
        #expect(await coordinator.snapshot().state == .running)
        #expect(await coordinator.pendingFailure == nil)
    }

    @Test func aStopWhileAFailureWaitsEndsAsStopped() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let coordinator = harness.coordinator
        let plan = harness.plan([try harness.site("demo.test")])
        try await harness.ensure(plan)
        await harness.engine.holdNextPreflight()
        let ticket = await coordinator.ticket()
        let preflight = Task { try await coordinator.preflight(plan, ticket: ticket) }
        #expect(await waitUntil { await harness.engine.isHolding })
        await harness.engine.crash()
        #expect(await waitUntil { await coordinator.pendingFailure != nil })
        let stop = Task { await coordinator.stop() }
        #expect(await waitUntil { await coordinator.isStopRequested(since: ticket) })
        await harness.engine.resumeHeld()
        await #expect(throws: CancellationError.self) { try await preflight.value }
        await stop.value
        #expect(await coordinator.snapshot().state == .stopped)
        #expect(await harness.system.released == 1)
    }
}

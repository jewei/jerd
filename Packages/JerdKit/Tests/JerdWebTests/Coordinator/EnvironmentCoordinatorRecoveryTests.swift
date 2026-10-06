import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

/// Review final-domain-r1 M1: after a crash, a web process of the earlier run still holds 80 and
/// 443. A start must name process recovery, not "port occupied".
@Suite struct EnvironmentCoordinatorRecoveryTests {
    @Test func aLiveEarlierWebProcessGivesTheRecoveryMessageBeforeThePortCheck() async throws {
        let harness = try CoordinatorHarness(portsOccupied: true)
        defer { harness.remove() }
        let location = harness.layout.environment.processRecord(UUID())
        try OwnedDirectory.create(harness.layout.environment.processesDirectory)
        let current = try ProcessIdentity.capture(getpid())
        let record = ActiveRunRecord(
            processID: getpid(), runtimeID: "caddy", identity: current, controller: current, gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(record, to: location.recordFile)
        let plan = harness.plan([try harness.site("demo.test")])
        await #expect(
            throws: JerdError.unavailable(
                "A previous service process needs inspection (PID \(getpid())). Open Advanced → Process recovery. "
                    + "No process was signalled.")
        ) {
            try await harness.ensure(plan)
        }
        #expect(try ActiveRunRecordFile.read(location.recordFile) == record)
        #expect(await harness.system.acquired == 0)
        #expect(await harness.engine.starts == 0)
    }

    @Test func withoutAnEarlierRecordAnOccupiedPortIsStillNamed() async throws {
        let harness = try CoordinatorHarness(portsOccupied: true)
        defer { harness.remove() }
        let plan = harness.plan([try harness.site("demo.test")])
        await #expect(throws: JerdError.unavailable("Local port 80 is occupied. No process was stopped.")) {
            try await harness.ensure(plan)
        }
        #expect(await harness.engine.starts == 0)
    }

    /// Review final-domain-r1 L1: Stop shows a surviving web process, and a later start retries
    /// the stop first and does not start while the process lives.
    @Test func aSurvivingWebProcessFailsTheStopAndBlocksTheNextStart() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let coordinator = harness.coordinator
        let plan = harness.plan([try harness.site("demo.test")])
        try await harness.ensure(plan)
        await harness.engine.survive("A web process survived.")
        await coordinator.stop()
        #expect(await coordinator.snapshot().state == .failed("A web process survived."))
        await #expect(throws: JerdError.processFailed("A web process survived.")) { try await harness.ensure(plan) }
        #expect(await harness.engine.starts == 1)
        #expect(await coordinator.snapshot().state == .failed("A web process survived."))
        await harness.engine.survive(nil)
        try await harness.ensure(plan)
        #expect(await coordinator.snapshot().state == .running)
        await coordinator.stop()
        #expect(await coordinator.snapshot().state == .stopped)
    }
}

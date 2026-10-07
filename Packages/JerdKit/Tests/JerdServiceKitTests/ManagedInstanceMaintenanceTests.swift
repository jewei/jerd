import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@Suite struct ManagedInstanceMaintenanceTests {
    @Test func aLeaseStopsTheServerAndKeepsTheLockUntilItEnds() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        let lease = try await instance.beginMaintenance()
        #expect(lease.wasRunning)
        #expect(lease.guards(harness.lockFile))
        #expect(await instance.state == .stopped)
        #expect(!isLockFree(harness.lockFile))
        await #expect(throws: JerdError.unavailable("The fake service is busy.")) { try await instance.start() }
        await #expect(throws: JerdError.unavailable("The fake service is busy.")) { try await instance.stop() }
        await #expect(throws: JerdError.unavailable("The fake service is busy.")) {
            _ = try await instance.beginMaintenance()
        }
        await instance.endMaintenance(lease)
        #expect(isLockFree(harness.lockFile))
        #expect(!lease.guards(harness.lockFile))
    }

    @Test func aStartInsideALeaseKeepsTheLockAfterAFailure() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        #expect(!lease.wasRunning)
        harness.probe.always(.notReady("no"))
        await #expect(throws: (any Error).self) { try await instance.start(in: lease, with: harness.definition()) }
        #expect(!isLockFree(harness.lockFile))
        harness.probe.set([])
        try await instance.start(in: lease, with: harness.definition(name: "Updated"))
        #expect(await instance.definition.profile.name == "Updated")
        try await instance.stop(in: lease)
        #expect(!isLockFree(harness.lockFile))
        await instance.endMaintenance(lease, failure: "Update failed.")
        #expect(await instance.state == .failed(reason: "Update failed."))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func anEndedLeaseCannotBeUsedAgain() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        let lease = try await instance.beginMaintenance()
        await instance.endMaintenance(lease)
        await #expect(throws: JerdError.unavailable(ServiceMessages.staleLease)) {
            try await instance.start(in: lease, with: harness.definition())
        }
        await #expect(throws: JerdError.unavailable(ServiceMessages.staleLease)) {
            try await instance.replaceDefinition(harness.definition(), in: lease)
        }
    }

    @Test func aLeaseIsRefusedWhileAnotherJerdHoldsTheLock() async throws {
        let harness = try InstanceHarness()
        try OwnedDirectory.create(harness.folder)
        let other = try InstanceLock.acquire(at: harness.lockFile, messages: FakeServiceDefinition.messages.lock)
        defer { other.release() }
        let instance = harness.instance()
        await #expect(throws: JerdError.locked("Another Jerd process uses the fake service.")) {
            _ = try await instance.beginMaintenance()
        }
        await #expect(throws: JerdError.locked("Another Jerd process uses the fake service.")) {
            try await instance.start()
        }
    }

    @Test func aSetupPhaseStopsItsServerAndKeepsTheLock() async throws {
        let harness = try InstanceHarness()
        harness.lsof.setPorts([], for: 60_001)
        let instance = harness.instance(harness.definition(setup: true))
        try await instance.start()
        #expect(await harness.processes.requests.map(\.arguments) == [["--setup"], ["--serve"]])
        #expect(await harness.processes.stopPolicies.count == 1)
        #expect(await instance.state == .running(pid: 60_002))
        #expect(try ActiveRunRecordFile.read(harness.recordFile).processID == 60_002)
    }

    @Test func aSetupServerWithATCPListenerFailsTheStart() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance(harness.definition(setup: true))
        await #expect(throws: (any Error).self) { try await instance.start() }
        #expect(await harness.processes.requests.count == 1)
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aSetupStopTimeoutIsNotWaitedForTwice() async throws {
        let harness = try InstanceHarness()
        harness.lsof.setPorts([], for: 60_001)
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        let instance = harness.instance(harness.definition(setup: true))
        await #expect(throws: (any Error).self) { try await instance.start() }
        #expect(await harness.processes.stopPolicies.count == 1)
        #expect(await instance.state.processID == 60_001)
        #expect(!isLockFree(harness.lockFile))
    }
}

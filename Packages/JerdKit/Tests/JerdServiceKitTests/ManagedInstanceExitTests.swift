import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import Testing

@Suite struct ManagedInstanceExitTests {
    @Test func anExitIsReportedWithTheEndOfTheLog() async throws {
        let harness = try InstanceHarness()
        await harness.processes.setLogOutput("Out of memory with \(InstanceHarness.secret)\n")
        let instance = harness.instance()
        try await instance.start()
        #expect(await instance.refresh().processID != nil)
        await harness.processes.exitAll()
        await instance.refresh()
        await instance.waitForPendingStop()
        #expect(await instance.state == .failed(reason: "The fake process exited. Out of memory with [redacted]\n"))
        #expect(!exists(harness.recordFile))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func exitDetectionNeverWaitsForTheStopOfTheGroup() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        let pid = try #require(await instance.processID)
        await harness.processes.holdStops()
        await harness.processes.exitAll()
        // The refresh returns while the group stop still waits.
        #expect(await instance.refresh() == .stopping(pid: pid))
        #expect(await instance.refresh() == .stopping(pid: pid))
        await harness.processes.releaseStops()
        await instance.waitForPendingStop()
        guard case .failed = await instance.state else {
            Issue.record("Expected a failed instance")
            return
        }
    }

    @Test func aUserStopJoinsTheExitStopInsteadOfBeingBusy() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        await harness.processes.holdStops()
        await harness.processes.exitAll()
        await instance.refresh()
        let stop = Task { try await instance.stop() }
        #expect(await eventually { await harness.processes.heldStopCount == 1 })
        await harness.processes.releaseStops()
        try await stop.value
        #expect(await instance.state == .stopped)
        #expect(await harness.processes.stopPolicies.count == 1)
    }

    @Test func anExitedLeaderWithAStubbornChildBecomesStuck() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        let pid = try #require(await instance.processID)
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: false)])
        await harness.processes.exitAll()
        await instance.refresh()
        await instance.waitForPendingStop()
        guard case .stuck(let stuckPID, let reason) = await instance.state else {
            Issue.record("Expected a stuck instance")
            return
        }
        #expect(stuckPID == pid)
        #expect(reason.hasSuffix(ServiceMessages.childStillRunning))
        #expect(exists(harness.recordFile))
        #expect(!isLockFree(harness.lockFile))
        await #expect(throws: (any Error).self) { try await instance.start() }
        try await instance.stop()
        #expect(await instance.state == .stopped)
    }

    @Test func aRunningProcessIsNotTouchedByRefresh() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        for _ in 0..<3 { await instance.refresh() }
        #expect(await harness.processes.stopPolicies.isEmpty)
    }
}

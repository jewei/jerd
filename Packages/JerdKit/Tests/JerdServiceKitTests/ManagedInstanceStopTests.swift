import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@Suite struct ManagedInstanceStopTests {
    @Test func aStopIsGracefulAndReleasesEverything() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance(harness.definition(stopSignal: SIGINT))
        try await instance.start()
        try FileManager.default.createDirectory(at: harness.socketFolder, withIntermediateDirectories: false)
        try await instance.stop()
        #expect(await instance.state == .stopped)
        let policy = try #require(await harness.processes.stopPolicies.last)
        #expect(policy == .graceful(signal: SIGINT, timeout: .seconds(30)))
        #expect(policy.escalation == .never)
        #expect(!exists(harness.recordFile))
        #expect(!exists(harness.socketFolder))
        #expect(isLockFree(harness.lockFile))
        #expect(await !instance.holdsLock)
    }

    @Test func aStopTimeoutKeepsTheProcessLockAndRecordUntilARetrySucceeds() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        let pid = try #require(await instance.processID)
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        let message =
            "Fake service did not stop within 30 seconds. Its process is still tracked. "
            + "Retry Stop; Jerd did not force it to exit."
        await #expect(throws: JerdError.processFailed(message)) { try await instance.stop() }
        #expect(await instance.state == .stuck(pid: pid, reason: message))
        #expect(exists(harness.recordFile))
        #expect(!isLockFree(harness.lockFile))
        try await instance.stop()
        #expect(await instance.state == .stopped)
        #expect(isLockFree(harness.lockFile))
        #expect(await harness.processes.stopPolicies.allSatisfy { $0.escalation == .never })
    }

    @Test func aStopWithoutAProcessClearsAFailure() async throws {
        let harness = try InstanceHarness()
        harness.lsof.occupy(41_001)
        let instance = harness.instance()
        await #expect(throws: (any Error).self) { try await instance.start() }
        try await instance.stop()
        #expect(await instance.state == .stopped)
        #expect(await harness.processes.stopPolicies.isEmpty)
    }

    @Test func aChildReapedOutsideJerdWithAStaleRecordCountsAsStopped() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        await harness.processes.setStopOutcomes([.notOwned])
        try await instance.stop()
        #expect(await instance.state == .stopped)
        #expect(!exists(harness.recordFile))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aChildReapedOutsideJerdWithALiveGroupKeepsTheRecordForRecovery() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        await harness.processes.setStopOutcomes([.notOwned])
        harness.system.setSavedProcessesAlive(true)
        await #expect {
            try await instance.stop()
        } throws: { ($0 as? JerdError)?.message.hasPrefix(ServiceMessages.reapedOutside) == true }
        guard case .failed(let reason) = await instance.state else {
            Issue.record("Expected a failed instance")
            return
        }
        #expect(reason.contains("Open Advanced → Process recovery."))
        #expect(exists(harness.recordFile))
        // Recovery needs the lock; the record still blocks every start.
        #expect(isLockFree(harness.lockFile))
        await #expect(throws: (any Error).self) { try await instance.start() }
        #expect(exists(harness.recordFile))
    }
}

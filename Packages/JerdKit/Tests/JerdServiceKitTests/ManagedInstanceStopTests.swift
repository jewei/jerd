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

    @Test func aStopTimeoutRunsTheShutdownRequestOnceAndThenWaitsForTheExit() async throws {
        let harness = try InstanceHarness()
        var definition = harness.definition()
        definition.plan.shutdownRequest = shutdownRequest(in: harness)
        let instance = harness.instance(definition)
        try await instance.start()
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        try await instance.stop()
        #expect(await instance.state == .stopped)
        #expect(harness.commands.requests(named: "client").map(\.arguments) == [["SHUTDOWN", "SAVE"]])
        #expect(
            await harness.processes.stopPolicies == [
                .graceful(signal: SIGTERM, timeout: .seconds(30)), .graceful(signal: SIGTERM, timeout: .seconds(10)),
            ])
        #expect(!exists(harness.recordFile))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aProcessThatIgnoresTheShutdownRequestStaysTrackedAndIsNeverKilled() async throws {
        let harness = try InstanceHarness()
        var definition = harness.definition()
        definition.plan.shutdownRequest = shutdownRequest(in: harness)
        let instance = harness.instance(definition)
        try await instance.start()
        let pid = try #require(await instance.processID)
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true), .timedOut(leaderRunning: true)])
        await #expect(throws: JerdError.self) { try await instance.stop() }
        guard case .stuck(pid, _) = await instance.state else {
            Issue.record("Expected a stuck instance")
            return
        }
        #expect(harness.commands.requests(named: "client").count == 1)
        #expect(exists(harness.recordFile))
        #expect(!isLockFree(harness.lockFile))
        #expect(await harness.processes.stopPolicies.allSatisfy { $0.escalation == .never })
    }

    @Test func aStopTimeoutWithoutAShutdownRequestWaitsOnlyOnce() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        await #expect(throws: JerdError.self) { try await instance.stop() }
        #expect(await harness.processes.stopPolicies.count == 1)
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

    private func shutdownRequest(in harness: InstanceHarness) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: "/fake/bin/client"), arguments: ["SHUTDOWN", "SAVE"],
            workingDirectory: harness.folder)
    }
}

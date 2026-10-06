import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

/// Review final-domain-r1 M1: after a crash the earlier server still runs and listens. The start
/// and the state must name process recovery, not "port occupied" or "Stopped".
@Suite struct ManagedInstanceRecoveryTests {
    private static let recovery = JerdError.unavailable(
        "A previous service process needs inspection (PID 4242). Open Advanced → Process recovery. "
            + "No process was signalled.")

    /// Writes a record of PID 4242 that the fake observer reports as alive.
    private func writeLiveRecord(_ harness: InstanceHarness) throws -> ActiveRunRecord {
        try OwnedDirectory.create(harness.folder)
        let record = ActiveRunRecord(
            processID: 4_242, runtimeID: "fake-1.2.3",
            identity: ProcessIdentity(
                processID: 4_242, userID: geteuid(), startedSeconds: 1, startedMicroseconds: 1, bootSeconds: 1,
                executable: "/fake", auditWords: nil, bootSessionID: nil), controller: nil, gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(record, to: harness.recordFile)
        harness.system.setSavedProcessesAlive(true)
        return record
    }

    @Test func aLiveEarlierProcessOnTheServicePortGivesTheRecoveryMessage() async throws {
        let harness = try InstanceHarness()
        let record = try writeLiveRecord(harness)
        harness.lsof.occupy(41_001)
        let instance = harness.instance()
        await #expect(throws: Self.recovery) { try await instance.start() }
        #expect(await instance.state == .failed(reason: Self.recovery.message))
        #expect(try ActiveRunRecordFile.read(harness.recordFile) == record)
        #expect(!exists(harness.lockFile))
        #expect(harness.commands.requests.isEmpty)
        #expect(await harness.processes.requests.isEmpty)
        #expect(await harness.processes.stopPolicies.isEmpty)
    }

    @Test func refreshShowsALiveEarlierProcessAndClearsItAfterRecovery() async throws {
        let harness = try InstanceHarness()
        _ = try writeLiveRecord(harness)
        let instance = harness.instance()
        #expect(await instance.refresh() == .failed(reason: Self.recovery.message))
        #expect(await instance.refresh() == .failed(reason: Self.recovery.message))
        #expect(!exists(harness.lockFile))
        try FileManager.default.removeItem(at: harness.recordFile)
        #expect(await instance.refresh() == .stopped)
    }

    @Test func refreshKeepsAStaleRecordForTheLockedStartCheck() async throws {
        let harness = try InstanceHarness()
        let record = try writeLiveRecord(harness)
        harness.system.setSavedProcessesAlive(false)
        let instance = harness.instance()
        #expect(await instance.refresh() == .stopped)
        #expect(try ActiveRunRecordFile.read(harness.recordFile) == record)
    }

    @Test func refreshKeepsAnotherFailureText() async throws {
        let harness = try InstanceHarness()
        harness.lsof.occupy(41_001)
        let instance = harness.instance()
        await #expect(throws: (any Error).self) { try await instance.start() }
        _ = try writeLiveRecord(harness)
        let occupied = "Local port 41001 is occupied. No process was stopped."
        #expect(await instance.refresh() == .failed(reason: occupied))
    }
}

import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import Testing

@Suite struct ManagedInstanceStartTests {
    @Test func aStartRunsEveryStepAndHoldsTheLockAndRecord() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        let pid = try #require(await harness.processes.lastPID)
        #expect(await instance.state == .running(pid: pid))
        #expect(harness.events.events == ["prepare", "complete"])
        #expect(await instance.holdsLock)
        #expect(!isLockFree(harness.lockFile))
        let record = try ActiveRunRecordFile.read(harness.recordFile)
        #expect(record.processID == pid && record.runtimeID == "fake-1.2.3" && record.gracefulSignal == SIGTERM)
        #expect(mode(harness.folder) == 0o700)
        #expect(await harness.processes.requests.map(\.arguments) == [["--serve"]])
        let order = harness.commands.requests.map { $0.arguments.joined(separator: " ") }
        #expect(order.first == "-nP -a -iTCP:41001 -sTCP:LISTEN -Fp")
        #expect(order.contains("--version"))
    }

    @Test func anOccupiedPortCreatesNoFileAndStartsNothing() async throws {
        let harness = try InstanceHarness()
        harness.lsof.occupy(41_001)
        let instance = harness.instance()
        await #expect(throws: JerdError.unavailable("Local port 41001 is occupied. No process was stopped.")) {
            try await instance.start()
        }
        #expect(await instance.state == .failed(reason: "Local port 41001 is occupied. No process was stopped."))
        #expect(!exists(harness.folder))
        #expect(await harness.processes.requests.isEmpty)
        #expect(harness.events.events.isEmpty)
    }

    @Test func aVersionMismatchStopsBeforeAnyDataStep() async throws {
        let harness = try InstanceHarness()
        harness.setVersionOutput("server 1.2.30")
        let instance = harness.instance()
        await #expect(throws: JerdError.unavailable("The fake server version does not match.")) {
            try await instance.start()
        }
        #expect(harness.events.events.isEmpty)
        #expect(await !instance.holdsLock)
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aLiveEarlierProcessBlocksTheStartAndIsNeverSignalled() async throws {
        let harness = try InstanceHarness()
        try OwnedDirectory.create(harness.folder)
        let record = ActiveRunRecord(
            processID: 4_242, runtimeID: "fake-1.2.3",
            identity: ProcessIdentity(
                processID: 4_242, userID: geteuid(), startedSeconds: 1, startedMicroseconds: 1, bootSeconds: 1,
                executable: "/fake", auditWords: nil, bootSessionID: nil), controller: nil, gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(record, to: harness.recordFile)
        harness.system.setSavedProcessesAlive(true)
        let instance = harness.instance()
        await #expect {
            try await instance.start()
        } throws: { ($0 as? JerdError)?.message.contains("needs inspection (PID 4242)") == true }
        #expect(try ActiveRunRecordFile.read(harness.recordFile) == record)
        #expect(await harness.processes.stopPolicies.isEmpty)
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aStaleEarlierRecordIsRemovedUnderTheLock() async throws {
        let harness = try InstanceHarness()
        try OwnedDirectory.create(harness.folder)
        let stale = ActiveRunRecord(
            processID: 4_242, runtimeID: "old", identity: nil, controller: nil, gracefulSignal: SIGTERM)
        try ActiveRunRecordFile.write(stale, to: harness.recordFile)
        let instance = harness.instance()
        try await instance.start()
        #expect(try ActiveRunRecordFile.read(harness.recordFile).runtimeID == "fake-1.2.3")
    }

    @Test func aReadinessTimeoutStopsTheProcessAndReleasesTheLock() async throws {
        let harness = try InstanceHarness()
        harness.probe.always(.notReady("denied for \(InstanceHarness.secret)"))
        let instance = harness.instance()
        await #expect(throws: JerdError.timedOut("The fake service timed out. denied for [redacted]")) {
            try await instance.start()
        }
        #expect(await instance.state == .failed(reason: "The fake service timed out. denied for [redacted]"))
        #expect(await harness.processes.stopPolicies == [.graceful(signal: SIGTERM)])
        #expect(!exists(harness.recordFile))
        #expect(!exists(harness.socketFolder))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aTimeoutWithTheLogDetailNamesTheEndOfTheLog() async throws {
        let harness = try InstanceHarness()
        await harness.processes.setLogOutput("fatal: bad config\n")
        harness.probe.always(.notReady("no"))
        let instance = harness.instance(harness.definition(detail: .logTail))
        await #expect(throws: JerdError.timedOut("The fake service timed out. fatal: bad config\n")) {
            try await instance.start()
        }
    }

    @Test func anExitBeforeReadinessReportsTheRedactedLog() async throws {
        let harness = try InstanceHarness()
        await harness.processes.setLogOutput("password \(InstanceHarness.secret) rejected")
        let processes = harness.processes
        harness.probe.setHook { await processes.exitAll() }
        harness.probe.always(.notReady("wait"))
        let instance = harness.instance()
        await #expect(throws: JerdError.processFailed("The fake service exited early. password [redacted] rejected")) {
            try await instance.start()
        }
    }

    @Test func anUnexpectedListenerFailsTheStart() async throws {
        let harness = try InstanceHarness()
        harness.lsof.addListener("*:41001")
        let instance = harness.instance()
        await #expect(
            throws: JerdError.processFailed(
                "The service opened an unexpected network listener. Expected loopback only.")
        ) { try await instance.start() }
        #expect(await harness.processes.runningPIDs.isEmpty)
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aStopTimeoutAfterAFailedStartKeepsTheProcessLockAndRecord() async throws {
        let harness = try InstanceHarness()
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        harness.probe.always(.notReady("no"))
        let instance = harness.instance()
        await #expect(throws: (any Error).self) { try await instance.start() }
        let pid = try #require(await harness.processes.lastPID)
        guard case .stuck(let stuckPID, let reason) = await instance.state else {
            Issue.record("Expected a stuck instance")
            return
        }
        #expect(stuckPID == pid)
        #expect(
            reason.hasSuffix(
                "Fake service did not stop within 30 seconds. Its process is still tracked. Retry Stop; Jerd did not force it to exit."
            ))
        #expect(exists(harness.recordFile))
        #expect(!isLockFree(harness.lockFile))
        await #expect(throws: JerdError.unavailable("The fake service already has a process.")) {
            try await instance.start()
        }
    }

    @Test func aFailedStepKeepsItsErrorKind() async throws {
        let harness = try InstanceHarness()
        var definition = harness.definition()
        definition.prepareError = .corrupt("The data is corrupt.")
        let instance = harness.instance(definition)
        await #expect(throws: JerdError.corrupt("The data is corrupt.")) { try await instance.start() }
        #expect(await harness.processes.requests.isEmpty)
    }

    @Test func aSpawnWithoutAnOwnedChildFailsWithTheLog() async throws {
        let harness = try InstanceHarness()
        await harness.processes.setOwnsNewChildren(false)
        await harness.processes.setLogOutput("cannot exec")
        let instance = harness.instance()
        await #expect(throws: JerdError.processFailed("The fake process could not start. cannot exec")) {
            try await instance.start()
        }
        #expect(!exists(harness.recordFile))
    }

    @Test func aSecondStartWhileStartingIsBusy() async throws {
        let harness = try InstanceHarness()
        let gate = Gate()
        harness.probe.setHook { await gate.wait() }
        let instance = harness.instance()
        let first = Task { try await instance.start() }
        #expect(await eventually { await gate.waiters == 1 })
        #expect(await instance.state == .starting)
        await #expect(throws: JerdError.unavailable("The fake service is busy.")) { try await instance.start() }
        await #expect(throws: JerdError.unavailable("The fake service is busy.")) { try await instance.stop() }
        await gate.open()
        try await first.value
        #expect(await instance.state.processID != nil)
    }

    @Test func theDefinitionChangesOnlyWithoutAProcess() async throws {
        let harness = try InstanceHarness()
        let instance = harness.instance()
        try await instance.start()
        await #expect(throws: JerdError.unavailable("The fake service is busy.")) {
            try await instance.replaceDefinition(harness.definition(name: "Renamed"))
        }
        try await instance.stop()
        try await instance.replaceDefinition(harness.definition(name: "Renamed"))
        #expect(await instance.definition.profile.name == "Renamed")
    }
}

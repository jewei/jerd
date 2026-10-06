import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

/// An initializer runs as an owned process of the instance: with a run record, with the lock
/// held, and with the graceful stop policy. A stop timeout keeps it owned.
@Suite struct ManagedInstanceInitializerTests {
    static let message = "The fake initializer timed out."

    private func definition(_ harness: InstanceHarness, secretFile: URL? = nil) -> FakeServiceDefinition {
        var definition = harness.definition()
        definition.initializer = InitializerPlan(
            request: ProcessRequest(
                executable: URL(fileURLWithPath: "/fake/bin/initializer"), arguments: ["--initialize"],
                workingDirectory: harness.folder),
            timeout: .seconds(120), timeoutMessage: Self.message, secrets: [InstanceHarness.secret],
            secretFiles: secretFile.map { [$0] } ?? [])
        return definition
    }

    /// A fake supervisor in which the initializer exits at once with `status`, or keeps running.
    private func harness(initializerStatus status: Int32?, output: String = "") throws -> InstanceHarness {
        try InstanceHarness(exitScript: { request in
            guard request.arguments == ["--initialize"], let status else { return nil }
            return FakeProcessController.ScriptedExit(status: status, output: output)
        })
    }

    @Test func anInitializerRunsOwnedAndReturnsItsStatusAndRedactedOutput() async throws {
        let harness = try harness(initializerStatus: 3, output: "created with \(InstanceHarness.secret)")
        let secretFile = harness.folder.appendingPathComponent("init-password")
        try write(InstanceHarness.secret, to: secretFile)
        let instance = harness.instance(definition(harness, secretFile: secretFile))
        try await instance.start()
        #expect(harness.events.events == ["prepare", "initializer 3 created with [redacted]", "complete"])
        #expect(await harness.processes.requests.map(\.arguments) == [["--initialize"], ["--serve"]])
        let policy = try #require(await harness.processes.stopPolicies.first)
        #expect(policy == .graceful(signal: SIGTERM, timeout: .seconds(30)))
        #expect(policy.escalation == .never)
        #expect(!exists(secretFile))
        #expect(await instance.state.processID != nil)
    }

    @Test func aTimedOutInitializerIsStoppedAndTheStartFailsWithTheTimeout() async throws {
        let harness = try harness(initializerStatus: nil)
        await harness.processes.setLogOutput("waiting for disk \(InstanceHarness.secret)")
        let instance = harness.instance(definition(harness))
        await #expect(throws: JerdError.timedOut("\(Self.message) waiting for disk [redacted]")) {
            try await instance.start()
        }
        #expect(await instance.state == .failed(reason: "\(Self.message) waiting for disk [redacted]"))
        #expect(await harness.processes.runningPIDs.isEmpty)
        #expect(!exists(harness.recordFile))
        #expect(isLockFree(harness.lockFile))
        #expect(harness.events.events == ["prepare"])
    }

    @Test func anInitializerThatIgnoresItsStopKeepsTheLockAndRecordUntilAStop() async throws {
        let harness = try harness(initializerStatus: nil)
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true), .timedOut(leaderRunning: true)])
        let instance = harness.instance(definition(harness))
        await #expect(throws: (any Error).self) { try await instance.start() }
        let pid = try #require(await harness.processes.lastPID)
        guard case .stuck(pid, let reason) = await instance.state else {
            Issue.record("Expected a stuck initializer, got \(await instance.state)")
            return
        }
        #expect(reason.hasPrefix("\(Self.message) Fake service did not stop within 30 seconds."))
        #expect(try ActiveRunRecordFile.read(harness.recordFile).processID == pid)
        #expect(!isLockFree(harness.lockFile))
        await #expect(throws: (any Error).self) { try await instance.stop() }
        #expect(!isLockFree(harness.lockFile))
        try await instance.stop()
        #expect(await instance.state == .stopped)
        #expect(!exists(harness.recordFile))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func anInitializerReapedOutsideJerdHasNoResultAndItsDataIsNotUsed() async throws {
        let harness = try harness(initializerStatus: nil)
        await harness.processes.setReapsOnWait(true)
        let instance = harness.instance(definition(harness))
        await #expect(throws: JerdError.processFailed(ServiceMessages.initializerResultUnknown)) {
            try await instance.start()
        }
        #expect(harness.events.events == ["prepare"])
        #expect(!exists(harness.recordFile))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func startToolsWithoutAnInitializerRunnerRefuse() async throws {
        let harness = try InstanceHarness()
        let tools = StartTools(commands: harness.commands, setup: RefusingSetup())
        let plan = try #require(definition(harness).initializer)
        await #expect(throws: JerdError.unavailable(ServiceMessages.initializerUnavailable)) {
            _ = try await tools.runInitializer(plan)
        }
        #expect(await harness.processes.requests.isEmpty)
    }
}

/// A setup runner for tools that a test never uses for a setup phase.
private struct RefusingSetup: SetupPhaseRunning {
    func runSetupPhase(_ plan: LaunchPlan) async throws {
        throw JerdError.unavailable("No setup phase in this test.")
    }
}

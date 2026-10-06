import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

/// Review final-domain-r1 L1: a web process that is still running after its stop keeps the run,
/// its records, and the environment lock, and the state says so. A later stop retries.
@Suite struct EngineRunnerSurvivorTests {
    private func recordNames(_ layout: RunLayout) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: layout.environment.processesDirectory.path)
            .filter { $0.hasSuffix(".json") }
    }

    private func isLockHeld(_ layout: RunLayout) -> Bool {
        do {
            let lock = try InstanceLock.acquire(
                at: layout.environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
            lock.release()
            return false
        } catch {
            return true
        }
    }

    @Test func aSurvivingCaddyKeepsTheRunTheRecordsAndTheLock() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        _ = try await harness.start(try harness.plan(), layout: layout)
        await harness.processes.survive(where: "run")
        await harness.engine.stop()
        #expect(await harness.engine.state == .failed(EngineRunner.survivorMessage))
        #expect(try recordNames(layout).count == 2)
        #expect(isLockHeld(layout))
        #expect(!isAbsent(layout.socketDirectory))
        await #expect(throws: JerdError.processFailed("The engine is already active.")) {
            try await harness.start(try harness.plan(), layout: try harness.layout())
        }
        await harness.processes.survive(where: nil)
        await harness.engine.stop()
        #expect(await harness.engine.state == .stopped)
        #expect(try recordNames(layout).isEmpty)
        #expect(!isLockHeld(layout))
        #expect(isAbsent(layout.socketDirectory))
    }

    @Test func aSurvivorAfterARuntimeExitIsAddedToTheExitFailure() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let run = try await harness.start(try harness.plan(), layout: layout)
        await harness.processes.survive(where: "run")
        let failure = Task { await harness.engine.waitForFailure(of: run) }
        await harness.processes.crash(where: "-F")
        #expect(await failure.value == EngineRunner.exitMessage)
        let expected = EnvironmentState.failed("\(EngineRunner.exitMessage) \(EngineRunner.survivorMessage)")
        // The state follows the stop, which ends after the waiters learned the failure.
        #expect(await waitUntil { await harness.engine.state == expected })
        #expect(isLockHeld(layout))
        await harness.processes.survive(where: nil)
        await harness.engine.stop()
        #expect(await harness.engine.state == .stopped)
    }
}

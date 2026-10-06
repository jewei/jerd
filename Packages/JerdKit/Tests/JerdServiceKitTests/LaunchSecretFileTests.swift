import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

/// `LaunchPlan.secretFiles` hold a secret that a process reads only while it starts. They are
/// removed when its readiness check ends, and a failed removal is reported.
@Suite struct LaunchSecretFileTests {
    private func secret(_ harness: InstanceHarness, _ name: String = "bootstrap.sql") throws -> URL {
        let file = harness.folder.appendingPathComponent(name)
        try write("password \(InstanceHarness.secret)", to: file)
        return file
    }

    @Test func setupSecretFilesAreRemovedWhenReadinessEndsAlsoWhenTheStopTimesOut() async throws {
        let harness = try InstanceHarness()
        var definition = harness.definition(setup: true)
        let file = try secret(harness)
        definition.setupPlan?.secretFiles = [file]
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        let instance = harness.instance(definition)
        await #expect(throws: (any Error).self) { try await instance.start() }
        guard case .stuck = await instance.state else {
            Issue.record("Expected a stuck instance, got \(await instance.state)")
            return
        }
        #expect(!exists(file))
        #expect(exists(harness.recordFile))
        #expect(!isLockFree(harness.lockFile))
    }

    @Test func aFailedReadinessCheckRemovesTheSecretFiles() async throws {
        let harness = try InstanceHarness()
        var definition = harness.definition()
        let file = try secret(harness, "client.cnf")
        definition.plan.secretFiles = [file]
        harness.probe.always(.notReady("no"))
        let instance = harness.instance(definition)
        await #expect(throws: JerdError.timedOut("The fake service timed out. no")) { try await instance.start() }
        #expect(!exists(file))
    }

    @Test func aSecretFileThatCannotBeRemovedFailsTheStartAndIsNamed() async throws {
        let harness = try InstanceHarness()
        var definition = harness.definition()
        let locked = harness.folder.appendingPathComponent("locked", isDirectory: true)
        let file = try secret(harness, "locked/secret.cnf")
        definition.plan.secretFiles = [file]
        chmod(locked.path, 0o500)
        defer { chmod(locked.path, 0o700) }
        let instance = harness.instance(definition)
        await #expect {
            try await instance.start()
        } throws: { error in
            let message = (error as? JerdError)?.message ?? ""
            return message.hasPrefix("Cannot remove \(file.path)")
                && message.hasSuffix("It holds a secret. Remove it by hand.")
        }
        #expect(exists(file))
        #expect(await harness.processes.runningPIDs.isEmpty)
        #expect(await instance.state.failure?.contains("It holds a secret.") == true)
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aDiscardedPlanRemovesItsSecretFilesAndKeepsTheError() throws {
        let harness = try InstanceHarness()
        var plan = harness.definition().plan
        let file = try secret(harness)
        plan.secretFiles = [file]
        let error = plan.discard(after: JerdError.invalid("The configuration could not be written."))
        #expect(error as? JerdError == JerdError.invalid("The configuration could not be written."))
        #expect(!exists(file))
    }
}

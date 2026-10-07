import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

/// `LaunchPlan.didStop` releases resources that are not files, for example the URL session of
/// storage. It must run once for every end of a launch, and never while the process lives.
@Suite struct LaunchStopHookTests {
    private func instance(_ harness: InstanceHarness) -> ManagedInstance {
        var definition = harness.definition()
        let events = harness.events
        definition.plan.didStop = { events.add("didStop") }
        return harness.instance(definition)
    }

    private func stopHooks(_ harness: InstanceHarness) -> Int {
        harness.events.events.filter { $0 == "didStop" }.count
    }

    @Test func aUserStopRunsTheHookOnceAfterTheTemporaryItemsAreGone() async throws {
        let harness = try InstanceHarness()
        let instance = instance(harness)
        try await instance.start()
        try FileManager.default.createDirectory(at: harness.socketFolder, withIntermediateDirectories: false)
        #expect(stopHooks(harness) == 0)
        try await instance.stop()
        #expect(stopHooks(harness) == 1)
        #expect(!exists(harness.socketFolder))
        try await instance.stop()
        #expect(stopHooks(harness) == 1)
    }

    @Test func aStopTimeoutDoesNotRunTheHookUntilARetryStops() async throws {
        let harness = try InstanceHarness()
        let instance = instance(harness)
        try await instance.start()
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        await #expect(throws: (any Error).self) { try await instance.stop() }
        #expect(stopHooks(harness) == 0)
        try await instance.stop()
        #expect(stopHooks(harness) == 1)
    }

    @Test func anExitStopRunsTheHook() async throws {
        let harness = try InstanceHarness()
        let instance = instance(harness)
        try await instance.start()
        await harness.processes.exitAll()
        await instance.refresh()
        await instance.waitForPendingStop()
        #expect(stopHooks(harness) == 1)
    }

    @Test func aReapOutsideJerdRunsTheHook() async throws {
        let harness = try InstanceHarness()
        let instance = instance(harness)
        try await instance.start()
        await harness.processes.setStopOutcomes([.notOwned])
        try await instance.stop()
        #expect(stopHooks(harness) == 1)
    }

    @Test func aLaunchWithoutAnOwnedChildRunsTheHook() async throws {
        let harness = try InstanceHarness()
        await harness.processes.setOwnsNewChildren(false)
        let instance = instance(harness)
        await #expect(throws: (any Error).self) { try await instance.start() }
        #expect(stopHooks(harness) == 1)
    }
}

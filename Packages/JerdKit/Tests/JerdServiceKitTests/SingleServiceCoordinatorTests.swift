import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

/// The manager core that Mail and Storage share. Each rule here holds for both services.
@Suite struct SingleServiceCoordinatorTests {
    typealias Coordinator = SingleServiceCoordinator<FakeSingleService>

    static let runtime = FakeRuntime(name: "old runtime")

    private func makeCoordinator(_ harness: InstanceHarness) -> (Coordinator, FakeSingleService) {
        let service = FakeSingleService(harness: harness)
        return (Coordinator(service: service, effects: harness.effects(), settings: FakeSingleSettings()), service)
    }

    private func loaded(_ harness: InstanceHarness) async throws -> (Coordinator, FakeSingleService) {
        let (coordinator, service) = makeCoordinator(harness)
        _ = try await coordinator.load()
        try await coordinator.registerRuntime(Self.runtime)
        return (coordinator, service)
    }

    @Test func everyOperationBeforeLoadIsRefused() async throws {
        let harness = try InstanceHarness()
        let (coordinator, _) = makeCoordinator(harness)
        let notLoaded = FakeSingleService.messages.notLoaded
        await #expect(throws: notLoaded) { try await coordinator.start() }
        await #expect(throws: notLoaded) { try await coordinator.stop() }
        await #expect(throws: notLoaded) { try await coordinator.registerRuntime(Self.runtime) }
        await #expect(throws: notLoaded) { try await coordinator.suggestedPorts() }
        await #expect(throws: notLoaded) { try await coordinator.edit(ports: FakePorts(port: 41_002)) }
        await #expect(throws: notLoaded) { try await coordinator.updateRuntime(FakeRuntime(name: "new")) }
        #expect(!exists(harness.folder))
    }

    @Test func oneOperationRunsAtATimeAndExitDetectionNeverWaits() async throws {
        let harness = try InstanceHarness()
        let (coordinator, _) = try await loaded(harness)
        try await coordinator.start()
        await harness.processes.holdStops()
        let stop = Task { try await coordinator.stop() }
        #expect(await eventually { await harness.processes.heldStopCount == 1 })
        let busy = JerdError.unavailable(FakeSingleService.messages.busy)
        await #expect(throws: busy) { try await coordinator.start() }
        await #expect(throws: busy) { try await coordinator.edit(ports: FakePorts(port: 41_002)) }
        #expect(await coordinator.snapshot().state.isBusy)
        await harness.processes.releaseStops()
        try await stop.value
        #expect(await coordinator.snapshot().state == .stopped)
    }

    @Test func aSavedRuntimeNeverChangesThroughRegistration() async throws {
        let harness = try InstanceHarness()
        let (coordinator, service) = try await loaded(harness)
        try await coordinator.registerRuntime(Self.runtime)
        await #expect(throws: FakeSingleService.messages.runtimeChanged) {
            try await coordinator.registerRuntime(FakeRuntime(name: "other"))
        }
        #expect(service.saved?.runtime == Self.runtime)
        let (fresh, _) = makeCoordinator(try InstanceHarness())
        _ = try await fresh.load()
        await #expect(throws: FakeSingleService.messages.runtimeRecordInvalid) {
            try await fresh.registerRuntime(FakeRuntime(name: ""))
        }
    }

    @Test func aFailedSaveOfNewPortsEndsTheLeaseAndKeepsTheSettings() async throws {
        let harness = try InstanceHarness()
        let (coordinator, service) = try await loaded(harness)
        let failure = JerdError.unavailable("The disk is full.")
        service.setSaveError(failure)
        await #expect(throws: failure) { try await coordinator.edit(ports: FakePorts(port: 41_002)) }
        #expect(isLockFree(harness.lockFile))
        #expect(await coordinator.settings.ports == FakePorts(port: 41_001))
        service.setSaveError(nil)
        try await coordinator.edit(ports: FakePorts(port: 41_002))
        #expect(service.saved?.ports == FakePorts(port: 41_002))
        #expect(isLockFree(harness.lockFile))
    }

    @Test func aPortEditNeedsAStoppedServiceAndClearsAnEarlierFailure() async throws {
        let harness = try InstanceHarness()
        let (coordinator, _) = try await loaded(harness)
        harness.setVersionOutput("server 9.9.9")
        await #expect(throws: JerdError.unavailable("The fake server version does not match.")) {
            try await coordinator.start()
        }
        #expect(await coordinator.snapshot().state.failure != nil)
        try await coordinator.edit(ports: FakePorts(port: 41_002))
        #expect(await coordinator.snapshot().state == .stopped)
        harness.setVersionOutput("server 1.2.3")
        try await coordinator.start()
        await #expect(throws: FakeSingleService.messages.stopBeforeEditing) {
            try await coordinator.edit(ports: FakePorts(port: 41_003))
        }
        try await coordinator.stop()
    }

    @Test func settingsChangeOnlyInsideAnOperation() async throws {
        let harness = try InstanceHarness()
        let (coordinator, service) = try await loaded(harness)
        await #expect(throws: JerdError.unavailable(FakeSingleService.messages.busy)) {
            try await coordinator.save(FakeSingleSettings(runtime: Self.runtime, ports: FakePorts(port: 41_009)))
        }
        #expect(service.saved?.ports == FakePorts(port: 41_001))
    }

    @Test func aPendingUpdateAllowsOnlyLoadStartAndStopAndStartRecoversIt() async throws {
        let harness = try InstanceHarness()
        let (coordinator, service) = try await loaded(harness)
        let lease = try await coordinator.requireInstance().beginMaintenance()
        _ = try await service.updateTransaction.beginBackup(holding: lease)
        try await coordinator.requireInstance().endMaintenance(lease)
        let pending = FakeSingleService.messages.updatePending
        await #expect(throws: pending) { try await coordinator.edit(ports: FakePorts(port: 41_002)) }
        await #expect(throws: pending) { try await coordinator.updateRuntime(FakeRuntime(name: "new")) }
        try await coordinator.stop()
        try await coordinator.start()
        #expect(!service.updateTransaction.isPending)
        #expect(await coordinator.snapshot().state.processID != nil)
        try await coordinator.stop()
    }

    @Test func aFailedUpdateOfAStoppedServiceRestoresItAndShowsStopped() async throws {
        let harness = try InstanceHarness()
        let (coordinator, service) = try await loaded(harness)
        harness.setVersionOutput("server 9.9.9")
        await #expect {
            try await coordinator.updateRuntime(FakeRuntime(name: "new runtime"))
        } throws: { error in
            (error as? JerdError)?.message.hasPrefix("Fake update failed. The previous runtime was restored.") == true
        }
        #expect(await coordinator.snapshot().state == .stopped)
        #expect(harness.events.events.prefix(2) == ["validate old runtime", "adopt new runtime"])
        #expect(await coordinator.settings.runtime == Self.runtime)
        #expect(!service.updateTransaction.isPending)
        #expect(isLockFree(harness.lockFile))
    }
}

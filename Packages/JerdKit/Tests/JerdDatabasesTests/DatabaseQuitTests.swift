import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdDatabases

@Suite struct DatabaseQuitTests {
    @Test func anExitStopInProgressDoesNotCancelQuit() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_500)
        try await manager.start(service.id)
        await harness.processes.holdStops()
        await harness.processes.exitAll()
        let pid = try #require(await manager.snapshot().state(of: service.id).processID)
        #expect(await manager.snapshot().state(of: service.id) == .stopping(pid: pid))
        let quit = Task { try await manager.stopAll() }
        #expect(await eventually { await harness.processes.heldStopCount == 1 })
        await harness.processes.releaseStops()
        try await quit.value
        #expect(await manager.snapshot().state(of: service.id) == .stopped)
    }

    @Test func aStartInProgressRefusesQuit() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_510)
        let gate = Gate()
        harness.update { $0.clientGate = gate }
        let start = Task { try await manager.start(service.id) }
        #expect(await eventually { await gate.waiters == 1 })
        await #expect(throws: DatabaseMessages.quitBusy) { try await manager.stopAll() }
        await gate.open()
        try await start.value
        try await manager.stopAll()
    }

    @Test func aStopTimeoutCancelsQuitAndKeepsTheLockAndRecord() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_520)
        try await manager.start(service.id)
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true), .timedOut(leaderRunning: true)])
        await #expect(
            throws: JerdError.processFailed(
                "Cache did not stop within 30 seconds. Its process is still tracked. Retry Stop; Jerd did not force it to exit."
            )
        ) { try await manager.stopAll() }
        let layout = harness.layout.instance(service.id)
        #expect(exists(layout.activeRunFile))
        #expect(!isLockFree(layout.lockFile))
        await #expect(throws: (any Error).self) { try await manager.remove(service.id) }
        try await manager.stopAll()
        #expect(isLockFree(layout.lockFile))
    }

    @Test func anUnexpectedExitIsReportedWithTheRedactedLog() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_530)
        try await manager.start(service.id)
        let password = try DatabaseCredentials.read(from: harness.files(service.id).layout.credentialsFile).password
        try write("auth \(password) failed\n", to: harness.layout.instance(service.id).logFile)
        await harness.processes.exitAll()
        _ = await manager.snapshot()
        #expect(
            await eventually {
                await manager.snapshot().state(of: service.id)
                    == .failed(reason: "The database process exited. auth [redacted] failed\n")
            })
    }
}

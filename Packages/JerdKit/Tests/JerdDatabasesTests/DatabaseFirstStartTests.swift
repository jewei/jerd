import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdDatabases

/// The first start of a service: the initializer, the setup phase, and their files.
@Suite struct DatabaseFirstStartTests {
    @Test func aStuckSetupServerKeepsNoBootstrapFileWithThePassword() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Main", runtimeID: harness.runtime(.mysql).id, port: 23_310)
        // The first stop is the stop of the socket-only setup server.
        await harness.processes.setStopOutcomes([.timedOut(leaderRunning: true)])
        await #expect(throws: (any Error).self) { try await manager.start(service.id) }
        guard case .stuck = await manager.snapshot().state(of: service.id) else {
            Issue.record("Expected a stuck service")
            return
        }
        let files = harness.files(service.id)
        #expect(!exists(files.bootstrapSQL))
        #expect(!exists(files.bootstrapOptions))
        #expect(exists(files.layout.activeRunFile))
        #expect(!isLockFree(files.layout.lockFile))
        try await manager.stop(service.id)
        #expect(isLockFree(files.layout.lockFile))
    }

    @Test func anInitializerRunsAsAnOwnedProcessWithTheGracefulEngineStop() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Main", runtimeID: harness.runtime(.postgresql).id, port: 25_440)
        try await manager.start(service.id)
        let requests = await harness.processes.requests
        #expect(requests.map(\.executable.lastPathComponent) == ["initdb", "postgres"])
        let policies = await harness.processes.stopPolicies
        #expect(policies == [.graceful(signal: SIGINT, timeout: .seconds(30))])
        #expect(policies.allSatisfy { $0.escalation == .never })
        let files = harness.files(service.id)
        #expect(!exists(files.initPassword))
        #expect(exists(files.layout.initializedMarkerFile))
        #expect(await manager.snapshot().state(of: service.id).processID != nil)
        try await manager.stopAll()
    }

    @Test func aHungInitializerThatIgnoresItsStopKeepsTheLockAndRecordAndCancelsQuit() async throws {
        let harness = try DatabaseHarness()
        harness.update { $0.initializerStatus = nil }
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Main", runtimeID: harness.runtime(.mysql).id, port: 23_320)
        // The initializer ignores the stop of the start, of Quit, and of Remove.
        await harness.processes.setStopOutcomes(Array(repeating: .timedOut(leaderRunning: true), count: 3))
        await #expect(throws: (any Error).self) { try await manager.start(service.id) }
        let pid = try #require(await harness.processes.lastPID)
        guard case .stuck(pid, let reason) = await manager.snapshot().state(of: service.id) else {
            Issue.record("Expected a stuck initializer")
            return
        }
        #expect(reason.hasPrefix("Database initialization timed out. Main did not stop within 30 seconds."))
        let files = harness.files(service.id)
        #expect(try ActiveRunRecordFile.read(files.layout.activeRunFile).processID == pid)
        #expect(!isLockFree(files.layout.lockFile))
        // Quit is cancelled, and Remove cannot take the lock, while the initializer lives.
        await #expect(throws: (any Error).self) { try await manager.stopAll() }
        await #expect(throws: (any Error).self) { try await manager.remove(service.id) }
        #expect(!isLockFree(files.layout.lockFile))
        #expect(!exists(files.layout.removedRegistrationFile))
        try await manager.stop(service.id)
        #expect(await manager.snapshot().state(of: service.id) == .stopped)
        #expect(!exists(files.layout.activeRunFile))
        #expect(isLockFree(files.layout.lockFile))
        #expect(!exists(files.layout.initializedMarkerFile))
    }

    @Test func aTimedOutInitializerIsStoppedAndReportedWithItsRedactedLog() async throws {
        let harness = try DatabaseHarness()
        harness.update { $0.initializerStatus = nil }
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Main", runtimeID: harness.runtime(.postgresql).id, port: 25_441)
        await harness.processes.setLogOutput("waiting for the disk")
        await #expect(throws: JerdError.timedOut("Database initialization timed out. waiting for the disk")) {
            try await manager.start(service.id)
        }
        let files = harness.files(service.id)
        #expect(await harness.processes.runningPIDs.isEmpty)
        #expect(!exists(files.layout.activeRunFile))
        #expect(!exists(files.initPassword))
        #expect(isLockFree(files.layout.lockFile))
    }

    @Test func aFailedInitializerRedactsThePasswordAndLeavesNoMarker() async throws {
        let harness = try DatabaseHarness()
        harness.update {
            $0.initializerStatus = 1
            $0.initializerOutput = "FATAL: bad password {password}"
        }
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Main", runtimeID: harness.runtime(.postgresql).id, port: 25_442)
        await #expect(throws: JerdError.processFailed("Database initialization failed: FATAL: bad password [redacted]"))
        {
            try await manager.start(service.id)
        }
        let files = harness.files(service.id)
        #expect(!exists(files.layout.initializedMarkerFile))
        #expect(!exists(files.initPassword))
        #expect(isLockFree(files.layout.lockFile))
    }
}

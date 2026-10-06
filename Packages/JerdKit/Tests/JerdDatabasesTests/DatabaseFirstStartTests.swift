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
}

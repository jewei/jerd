import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing
import os

@testable import JerdStorage

/// Each RustFS launch has its own S3 session. `LaunchPlan.didStop` ends it after every kind of
/// stop, and the names of the launch go with it.
@Suite struct StorageLaunchTests {
    /// Counts the sessions that launches made and ended. Every session sends to the fake server.
    final class RecordingSessions: Sendable {
        private let counts = OSAllocatedUnfairLock(initialState: (made: 0, ended: 0))
        let server: FakeS3Server

        init(server: FakeS3Server) { self.server = server }

        var made: Int { counts.withLock { $0.made } }
        var ended: Int { counts.withLock { $0.ended } }

        func make() -> S3Session {
            counts.withLock { $0.made += 1 }
            return S3Session(sender: server, end: { [counts] in counts.withLock { $0.ended += 1 } })
        }
    }

    private func manager(_ harness: StorageHarness) async throws -> (StorageManager, RecordingSessions) {
        let sessions = RecordingSessions(server: harness.server)
        let manager = StorageManager(
            layout: harness.layout, effects: harness.effects(), makeSession: { sessions.make() },
            now: { StorageHarness.date })
        _ = try await manager.load()
        try await manager.registerRuntime(harness.runtime)
        harness.server.update { $0.buckets = ["app-uploads"] }
        return (manager, sessions)
    }

    @Test func aUserStopEndsTheSessionAndClearsTheNames() async throws {
        let harness = try await StorageHarness()
        let (manager, sessions) = try await manager(harness)
        try await manager.start()
        #expect(sessions.made == 1 && sessions.ended == 0)
        #expect(manager.launch.names == ["app-uploads"])
        try await manager.stop()
        #expect(sessions.ended == 1)
        #expect(manager.launch.names.isEmpty && manager.launch.current == nil)
        await #expect(throws: StorageMessages.startBeforeBuckets) { try await manager.refreshBuckets() }
    }

    @Test func anUnexpectedExitEndsTheSessionAndClearsTheNames() async throws {
        let harness = try await StorageHarness()
        let (manager, sessions) = try await manager(harness)
        try await manager.start()
        await harness.processes.exitAll()
        _ = await manager.snapshot()
        #expect(await eventually { sessions.ended == 1 })
        #expect(manager.launch.names.isEmpty && manager.launch.current == nil)
    }

    @Test func aFailedReadinessEndsTheSessionOfThatLaunch() async throws {
        let harness = try await StorageHarness()
        let (manager, sessions) = try await manager(harness)
        harness.server.update { $0.consoleStatus = 500 }
        await #expect {
            try await manager.start()
        } throws: { error in
            (error as? JerdError)?.kind == .timedOut
        }
        #expect(sessions.made == 1 && sessions.ended == 1)
        #expect(manager.launch.current == nil)
    }

    @Test func aRestartUsesANewSessionAndEndsTheOldOne() async throws {
        let harness = try await StorageHarness()
        let (manager, sessions) = try await manager(harness)
        try await manager.start()
        try await manager.stop()
        try await manager.start()
        #expect(sessions.made == 2 && sessions.ended == 1)
        #expect(manager.launch.names == ["app-uploads"])
        try await manager.stop()
        #expect(sessions.ended == 2)
    }

    @Test func aLateAnswerOfAnEndedLaunchChangesNothing() {
        let launch = StorageLaunch()
        let server = FakeS3Server()
        let first = launch.begin(.shared(server))
        launch.end(first)
        let second = launch.begin(.shared(server))
        launch.replaceNames(["old"], of: first)
        launch.insert("old", of: first)
        launch.end(first)
        #expect(launch.names.isEmpty && launch.current?.id == second)
    }
}

import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdProcess

/// Fixed review L11: these tests fail when the spawn attributes do not reset the signal state.
@Suite struct SpawnerSignalMaskTests {
    /// Spawns from the calling thread while `signal` is blocked in that thread only.
    private func spawn(_ plan: SpawnPlan, output: Int32, blocking signal: Int32) throws -> pid_t {
        var blocked = sigset_t()
        sigemptyset(&blocked)
        sigaddset(&blocked, signal)
        var previous = sigset_t()
        pthread_sigmask(SIG_BLOCK, &blocked, &previous)
        defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
        return try Spawner.spawn(plan, output: output, listeners: nil)
    }

    @Test func aSignalThatTheSpawningThreadBlocksIsNotBlockedInTheChild() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let executable = try await Fixtures.shared.executable("spawn-inspector")
        let plan = try SpawnPlan(request: ProcessRequest(executable: executable, workingDirectory: folder.url))
        let log = ProcessLogFile(url: folder.path("mask.log"))
        let handle = try log.create()
        let pid = try spawn(plan, output: handle.fileDescriptor, blocking: SIGUSR1)
        var status: Int32 = 0
        #expect(waitpid(pid, &status, 0) == pid)
        #expect(text(log.url).contains("blocked: 0\n"))
    }
}

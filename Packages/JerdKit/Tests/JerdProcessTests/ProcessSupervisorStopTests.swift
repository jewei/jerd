import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct ProcessSupervisorStopTests {
    private func start(
        _ fixture: String, _ arguments: [String] = [], in folder: TemporaryDirectory,
        using supervisor: ProcessSupervisor
    )
        async throws -> ProcessToken
    {
        let executable = try await Fixtures.shared.executable(fixture)
        let request = ProcessRequest(executable: executable, arguments: arguments, workingDirectory: folder.url)
        return try await supervisor.start(request, log: ProcessLogFile(url: folder.path("\(fixture).log")))
    }

    @Test func aGracefulTimeoutKeepsTheOwnedProcessForARetry() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let token = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await eventually { text(folder.path("graceful-process.log")) == "ready\n" })
        let pid = try #require(await supervisor.processID(of: token))
        #expect(
            await supervisor.stop(token, policy: .graceful(timeout: .milliseconds(80)))
                == .timedOut(leaderRunning: true))
        #expect(await supervisor.state(of: token) == .running)
        #expect(await supervisor.processID(of: token) == pid)
        #expect(await supervisor.stop(token, policy: .graceful(signal: SIGINT, timeout: .seconds(3))) == .stopped)
    }

    /// Regression test: the default supervisor never kills, whatever policy a caller passes.
    @Test func aGracefulSupervisorDoesNotKillForAForcefulPolicy() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        #expect(await supervisor.ceiling == .graceful)
        let token = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await eventually { text(folder.path("graceful-process.log")) == "ready\n" })
        let policy = StopPolicy.forceful(leaderTimeout: .milliseconds(100), groupTimeout: .milliseconds(100))
        #expect(await supervisor.stop(token, policy: policy) == .timedOut(leaderRunning: true))
        #expect(await supervisor.state(of: token) == .running)
        #expect(await supervisor.stop(token, policy: .graceful(signal: SIGINT, timeout: .seconds(3))) == .stopped)
    }

    @Test func aForcefulStopKillsALeaderThatIgnoresTerminationWithinItsBudget() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor(ceiling: .forceful)
        let token = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await eventually { text(folder.path("graceful-process.log")) == "ready\n" })
        let pid = try #require(await supervisor.processID(of: token))
        let started = ContinuousClock.now
        let policy = StopPolicy.forceful(leaderTimeout: .milliseconds(100), groupTimeout: .milliseconds(100))
        let outcome = await supervisor.stop(token, policy: policy)
        #expect(outcome == .stopped, "\(outcome) after \(ContinuousClock.now - started)")
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(isGone(pid))
    }

    @Test(arguments: [false, true])
    func groupMembersAreStoppedAfterTheLeaderExits(graceful: Bool) async throws {
        let folder = try TemporaryDirectory(" process café")
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let marker = folder.path("clean-exit")
        let token = try await start("process-tree", graceful ? [marker.path] : [], in: folder, using: supervisor)
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
        let child = try #require(
            pid_t(text(folder.path("process-tree.log")).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(child, 0) == 0)
        let policy: StopPolicy = graceful ? .graceful(timeout: .seconds(3)) : .forceful()
        #expect(await supervisor.stop(token, policy: policy) == .stopped)
        #expect(await eventually { isGone(child) })
        if graceful { #expect(text(marker) == "clean") }
    }

    @Test func anExitedLeaderStaysOwnedWhileItsChildLives() async throws {
        let folder = try TemporaryDirectory(" early exit")
        defer { folder.remove() }
        touch(folder.path("exit-master"))
        let supervisor = ProcessSupervisor()
        let token = try await start("orphan-service", in: folder, using: supervisor)
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(3)) == .exited(status: 0))
        #expect(await supervisor.processID(of: token) != nil)
        let child = try #require(await waitForPID(in: folder.path("child.pid")))
        #expect(
            await supervisor.stop(token, policy: .graceful(timeout: .milliseconds(100)))
                == .timedOut(leaderRunning: false))
        #expect(kill(child, 0) == 0)
        touch(folder.path("finish-child"))
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(3))) == .stopped)
        #expect(await eventually { isGone(child) })
    }

    @Test func redactedOutputNeverReachesTheDisk() async throws {
        let folder = try TemporaryDirectory(" redacted-process")
        defer { folder.remove() }
        let secret = "test-only-private-value-12345"
        let supervisor = ProcessSupervisor()
        let log = ProcessLogFile(url: folder.path("process.log"))
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/printenv"), arguments: ["TEST_CREDENTIAL"],
            workingDirectory: folder.url, environment: ["TEST_CREDENTIAL": secret], redactedValues: [secret])
        let token = try await supervisor.start(request, log: log)
        while await supervisor.state(of: token) == .running {
            #expect(!text(log.url).contains(secret))
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(3))) == .stopped)
        #expect(text(log.url) == "[redacted]\n")
    }
}

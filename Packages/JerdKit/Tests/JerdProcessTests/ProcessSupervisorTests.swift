import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct ProcessSupervisorTests {
    private func request(
        _ executable: String, _ arguments: [String] = [], in folder: TemporaryDirectory
    )
        -> ProcessRequest
    {
        ProcessRequest(executable: URL(fileURLWithPath: executable), arguments: arguments, workingDirectory: folder.url)
    }

    @Test func exitStatesAreReadWithoutReapingUntilAStopCompletes() async throws {
        let folder = try TemporaryDirectory(" supervisor ü")
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let log = ProcessLogFile(url: folder.path("false.log"))
        let token = try await supervisor.start(request("/usr/bin/false", in: folder), log: log)
        #expect(await supervisor.waitForExit(of: token, timeout: .seconds(5)) == .exited(status: 1))
        let pid = try #require(await supervisor.processID(of: token))
        #expect(kill(pid, 0) == 0)  // A zombie still reserves the PID.
        #expect(await supervisor.stop(token, policy: .graceful(timeout: .seconds(1))) == .stopped)
        #expect(await supervisor.state(of: token) == .notOwned)
        #expect(await supervisor.processID(of: token) == nil)
        #expect(isGone(pid))
        #expect(await supervisor.stop(token, policy: .forceful()) == .stopped)
    }

    @Test func aSignalledChildReportsTheSignalAndTheShellStatus() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let token = try await supervisor.start(
            request("/bin/sleep", ["30"], in: folder), log: ProcessLogFile(url: folder.path("s.log")))
        #expect(await supervisor.state(of: token) == .running)
        let pid = try #require(await supervisor.processID(of: token))
        kill(pid, SIGKILL)
        let state = await supervisor.waitForExit(of: token, timeout: .seconds(5))
        #expect(state == .signalled(signal: SIGKILL))
        #expect(state.exitCode == 137)
        #expect(await supervisor.stop(token, policy: .graceful()) == .stopped)
    }

    @Test func waitingForExitUsesTheDeadlineAndReturnsAtOnceOnExit() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let sleeper = try await supervisor.start(
            request("/bin/sleep", ["30"], in: folder), log: ProcessLogFile(url: folder.path("a.log")))
        #expect(await supervisor.waitForExit(of: sleeper, timeout: .milliseconds(50)) == .running)
        let started = ContinuousClock.now
        let quick = try await supervisor.start(
            request("/usr/bin/true", in: folder), log: ProcessLogFile(url: folder.path("b.log")))
        #expect(await supervisor.waitForExit(of: quick, timeout: .seconds(20)) == .exited(status: 0))
        #expect(ContinuousClock.now - started < .seconds(5))
        let outcomes = await supervisor.stopAll(policy: .forceful())
        #expect(outcomes == [sleeper: .stopped, quick: .stopped])
    }

    @Test func aChildReapedOutsideTheSupervisorIsNotOwnedAndGetsNoSignal() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let token = try await supervisor.start(
            request("/usr/bin/true", in: folder), log: ProcessLogFile(url: folder.path("t.log")))
        let pid = try #require(await supervisor.processID(of: token))
        _ = await supervisor.waitForExit(of: token, timeout: .seconds(5))
        var status: Int32 = 0
        #expect(waitpid(pid, &status, 0) == pid)  // Someone else reaps the child.
        #expect(await supervisor.state(of: token) == .notOwned)
        #expect(await supervisor.processID(of: token) == nil)
        #expect(await supervisor.stop(token, policy: .graceful()) == .notOwned)
        #expect(await supervisor.stop(token, policy: .graceful()) == .notOwned)
    }

    @Test func aFailedLaunchCreatesNoLogAndAStartRecreatesTheLogEmpty() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let missing = ProcessLogFile(url: folder.path("missing.log"))
        await #expect(throws: JerdError.self) {
            try await supervisor.start(request("/missing/jerd-binary", in: folder), log: missing)
        }
        #expect(FileProbe.presence(at: missing.url) == .absent)
        let log = ProcessLogFile(url: folder.path("echo.log"))
        try Data("old output".utf8).write(to: log.url)
        let token = try await supervisor.start(request("/bin/echo", ["new"], in: folder), log: log)
        _ = await supervisor.waitForExit(of: token, timeout: .seconds(5))
        #expect(await supervisor.stop(token, policy: .forceful()) == .stopped)
        #expect(text(log.url) == "new\n")
        var info = stat()
        #expect(stat(log.url.path, &info) == 0 && info.st_mode & 0o777 == 0o600)
    }

    @Test func concurrentStopsOfOneTokenShareOneResult() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let token = try await supervisor.start(
            request("/bin/sleep", ["30"], in: folder), log: ProcessLogFile(url: folder.path("c.log")))
        async let first = supervisor.stop(token, policy: .graceful(timeout: .seconds(5)))
        async let second = supervisor.stop(token, policy: .graceful(timeout: .seconds(5)))
        let outcomes = await [first, second]
        #expect(outcomes == [.stopped, .stopped], "\(outcomes)")
    }
}

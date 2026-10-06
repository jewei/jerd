import Darwin
import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdProcess

/// A paused child (`SIGSTOP`, a debugger, a job-control stop) is alive. Darwin reports it to
/// `waitid(WEXITED)` with `CLD_STOPPED`, so the supervisor must not read that as an exit.
@Suite struct PausedProcessTests {
    private func start(
        _ fixture: String, _ arguments: [String] = [], in folder: TemporaryDirectory,
        using supervisor: ProcessSupervisor
    ) async throws -> (ProcessToken, pid_t) {
        let executable = try await Fixtures.shared.executable(fixture)
        let request = ProcessRequest(executable: executable, arguments: arguments, workingDirectory: folder.url)
        let token = try await supervisor.start(request, log: ProcessLogFile(url: folder.path("\(fixture).log")))
        #expect(await eventually { text(folder.path("\(fixture).log")) == "ready\n" })
        return (token, try #require(await supervisor.processID(of: token)))
    }

    @Test func onlyAnExitAKillOrADumpEndsAChild() {
        #expect(ChildStatus.state(code: CLD_EXITED, status: 3) == .exited(status: 3))
        #expect(ChildStatus.state(code: CLD_KILLED, status: SIGTERM) == .signalled(signal: SIGTERM))
        #expect(ChildStatus.state(code: CLD_DUMPED, status: SIGABRT) == .signalled(signal: SIGABRT))
        #expect(ChildStatus.state(code: CLD_STOPPED, status: SIGSTOP) == .running)
        #expect(ChildStatus.state(code: CLD_CONTINUED, status: SIGCONT) == .running)
        #expect(ChildStatus.state(code: CLD_TRAPPED, status: SIGTRAP) == .running)
    }

    @Test func aPausedChildIsReportedRunning() async throws {
        let folder = try TemporaryDirectory(" paused")
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let (token, pid) = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await ProcessPause.pause(pid))
        #expect(await supervisor.state(of: token) == .running)
        #expect(await supervisor.waitForExit(of: token, timeout: .milliseconds(100)) == .running)
        #expect(await supervisor.processID(of: token) == pid)
        kill(pid, SIGCONT)
        #expect(await supervisor.state(of: token) == .running)
        #expect(await supervisor.stop(token, policy: .graceful(signal: SIGINT, timeout: .seconds(3))) == .stopped)
    }

    /// A caught stop signal stays pending while the child is paused, so the stop continues it.
    @Test func aGracefulStopEndsAPausedChild() async throws {
        let folder = try TemporaryDirectory(" paused stop")
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let (token, pid) = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await ProcessPause.pause(pid))
        #expect(await supervisor.stop(token, policy: .graceful(signal: SIGINT, timeout: .seconds(3))) == .stopped)
        #expect(isGone(pid))
        #expect(await supervisor.state(of: token) == .notOwned)
    }

    @Test func aPausedChildThatIgnoresTheSignalTimesOutAndStaysOwned() async throws {
        let folder = try TemporaryDirectory(" paused timeout")
        defer { folder.remove() }
        let supervisor = ProcessSupervisor()
        let (token, pid) = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await ProcessPause.pause(pid))
        #expect(
            await supervisor.stop(token, policy: .graceful(timeout: .milliseconds(150)))
                == .timedOut(leaderRunning: true))
        #expect(await supervisor.state(of: token) == .running)
        #expect(await supervisor.processID(of: token) == pid)
        #expect(!ProcessPause.isPaused(pid))
        #expect(await supervisor.stop(token, policy: .graceful(signal: SIGINT, timeout: .seconds(3))) == .stopped)
    }

    /// The forceful engine continues a paused child too, so it can end on the first signal.
    @Test func aForcefulStopEndsAPausedChildWithItsFirstSignal() async throws {
        let folder = try TemporaryDirectory(" paused forceful")
        defer { folder.remove() }
        let supervisor = ProcessSupervisor(ceiling: .forceful)
        let (token, pid) = try await start("graceful-process", in: folder, using: supervisor)
        #expect(await ProcessPause.pause(pid))
        let policy = StopPolicy.forceful(signal: SIGINT, leaderTimeout: .seconds(3), killWait: .seconds(2))
        let started = ContinuousClock.now
        #expect(await supervisor.stop(token, policy: policy) == .stopped)
        // Without SIGCONT the signal stays pending and only the group kill after 3 s ends it.
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(isGone(pid))
    }
}

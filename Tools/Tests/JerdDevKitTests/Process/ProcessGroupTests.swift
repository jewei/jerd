import Foundation
import Testing
import os

@testable import JerdDevKit

/// Process groups, signal forwarding, and output collection. The real-process tests start small
/// system programs (one test uses a shell trap as a SIGTERM handler), and find leftover processes
/// by a unique argument.
@Suite("Process groups and signals")
struct ProcessGroupTests {
    /// A unique `sleep` duration, so that `ps` finds only the process of this test.
    private static func uniqueSleepSeconds() -> String {
        "41.\(Int.random(in: 100_000...999_999))"
    }

    /// The process IDs whose command line contains `marker`.
    private static func processes(containing marker: String) async throws -> [String] {
        let runner = ProcessRunner(output: RecordingTextOutput(), groups: ChildProcessGroups())
        let listing = try await runner.run(
            Invocation(
                executable: URL(filePath: "/bin/ps"), arguments: ["-axo", "pid=,command="], timeout: .seconds(30)),
            output: .capture)
        return listing.standardOutput.split(separator: "\n").filter { $0.contains(marker) }.map(String.init)
    }

    @Test("the time limit also stops a silent grandchild")
    func timeLimitStopsGrandchild() async throws {
        let seconds = Self.uniqueSleepSeconds()
        let runner = ProcessRunner(output: RecordingTextOutput(), killDelay: .seconds(1), groups: ChildProcessGroups())
        // `time` starts `sleep` as its own child and waits for it: the old runner killed only `time`.
        let command = Invocation(
            executable: URL(filePath: "/usr/bin/time"), arguments: ["/bin/sleep", seconds], timeout: .milliseconds(300))
        let result = try await runner.run(command, output: .capture)
        #expect(result.exceededTimeLimit != nil)
        #expect(try await Self.processes(containing: "sleep \(seconds)").isEmpty)
    }

    @Test("a paused child is not an exit: the run waits for its real end")
    func pausedChildIsNotAnExit() async throws {
        let groups = ChildProcessGroups()
        let runner = ProcessRunner(output: RecordingTextOutput(), groups: groups)
        let command = Invocation(executable: URL(filePath: "/bin/sleep"), arguments: ["30"], timeout: .seconds(60))
        let running = Task { try await runner.run(command, output: .capture) }
        while groups.running.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let group = try #require(groups.running.first)
        kill(group, SIGSTOP)
        try await Task.sleep(for: .milliseconds(300))
        #expect(groups.running == [group])
        kill(group, SIGKILL)
        let result = try await running.value
        #expect(result.status == 128 + SIGKILL)
    }

    @Test("the time limit continues a paused group, so a child that handles SIGTERM ends on its own")
    func timeLimitContinuesPausedGroup() async throws {
        let groups = ChildProcessGroups()
        let runner = ProcessRunner(output: RecordingTextOutput(), killDelay: .seconds(4), groups: groups)
        // A shell trap stands for a test runner that cleans up on SIGTERM and exits 0.
        let command = Invocation(
            executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "trap 'exit 0' TERM; while :; do /bin/sleep 0.05; done"],
            timeout: .seconds(1))
        let running = Task { try await runner.run(command, output: .capture) }
        while groups.running.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let group = try #require(groups.running.first)
        // Give the shell time to set its trap, then pause the whole group before the time limit.
        try await Task.sleep(for: .milliseconds(300))
        kill(-group, SIGSTOP)
        let result = try await running.value
        #expect(result.exceededTimeLimit != nil)
        // Without SIGCONT, the paused shell keeps SIGTERM pending and gets SIGKILL after the delay.
        #expect(result.status == 0)
    }

    @Test("only an exit, a kill, or a core dump ends a child")
    func onlyRealEndsAreStatuses() {
        #expect(ChildProcess.endStatus(code: CLD_EXITED, status: 3) == 3)
        #expect(ChildProcess.endStatus(code: CLD_KILLED, status: SIGTERM) == 128 + SIGTERM)
        #expect(ChildProcess.endStatus(code: CLD_DUMPED, status: SIGABRT) == 128 + SIGABRT)
        #expect(ChildProcess.endStatus(code: CLD_STOPPED, status: SIGSTOP) == nil)
        #expect(ChildProcess.endStatus(code: CLD_CONTINUED, status: SIGCONT) == nil)
    }

    @Test("a forwarded signal stops the running child group, and no new child starts after it")
    func forwardedSignalStopsChildren() async throws {
        let groups = ChildProcessGroups()
        let runner = ProcessRunner(output: RecordingTextOutput(), groups: groups)
        let command = Invocation(executable: URL(filePath: "/bin/sleep"), arguments: ["30"], timeout: .seconds(60))
        let running = Task { try await runner.run(command, output: .capture) }
        while groups.running.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        groups.signalAll(SIGINT, stopStarting: true)
        let result = try await running.value
        #expect(result.status == 128 + SIGINT)
        #expect(groups.running.isEmpty)
        await #expect(throws: InvocationFailure.self) {
            _ = try await runner.run(command, output: .capture)
        }
    }

    @Test("the forwarder signals every group, kills the groups that remain, and exits with 128 plus the signal")
    func forwarderEscalates() throws {
        let sent = OSAllocatedUnfairLock(initialState: [(pid_t, Int32)]())
        let groups = ChildProcessGroups { group, signal in sent.withLock { $0.append((group, signal)) } }
        _ = try groups.start(commandLine: "a") { 4242 }
        let forwarder = SignalForwarder(groups: groups, gracePeriod: .milliseconds(50))
        #expect(forwarder.interrupt(by: SIGTERM) == 143)
        #expect(groups.stopSignal == SIGTERM)
        let signals = sent.withLock { $0 }
        #expect(signals.map(\.0) == [4242, 4242])
        #expect(signals.map(\.1) == [SIGTERM, SIGKILL])
        #expect(throws: InvocationFailure.self) {
            _ = try groups.start(commandLine: "b") { 4343 }
        }
    }

    @Test("forwards only the signals that stop a command")
    func forwardsStopSignals() {
        #expect(SignalForwarder.forwardedSignals == [SIGINT, SIGTERM, SIGHUP])
    }

    @Test("the child gets default signal actions even when ./dev ignores a signal")
    func childGetsDefaultSignals() async throws {
        let previous = signal(SIGUSR1, SIG_IGN)
        defer { signal(SIGUSR1, previous) }
        let groups = ChildProcessGroups()
        let runner = ProcessRunner(output: RecordingTextOutput(), groups: groups)
        let command = Invocation(executable: URL(filePath: "/bin/sleep"), arguments: ["30"], timeout: .seconds(60))
        let running = Task { try await runner.run(command, output: .capture) }
        while groups.running.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        groups.signalAll(SIGUSR1)
        #expect(try await running.value.status == 128 + SIGUSR1)
    }

    @Test("keeps the end of a long output and prints filtered lines per channel")
    func collectsTail() {
        let output = RecordingTextOutput()
        let collector = OutputCollector(
            channel: .standardError, mode: .streamMatching { $0.hasPrefix("keep") }, output: output, byteLimit: 8)
        for index in 0..<10 {
            collector.append(Data("line\(index)\n".utf8))
        }
        collector.append(Data("keep".utf8))
        collector.finish()
        #expect(collector.text == "ne9\nkeep")
        #expect(output.standardError == "keep\n")
    }
}

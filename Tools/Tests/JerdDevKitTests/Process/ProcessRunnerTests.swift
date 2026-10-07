import Foundation
import Testing

@testable import JerdDevKit

/// These tests start small system programs. They need no network, no root, and no shell.
@Suite("Process runner")
struct ProcessRunnerTests {
    private func invocation(_ path: String, _ arguments: [String], timeout: Duration = .seconds(30)) -> Invocation {
        Invocation(executable: URL(filePath: path), arguments: arguments, timeout: timeout)
    }

    @Test("captures standard output and the exit status")
    func capturesOutput() async throws {
        let runner = ProcessRunner(output: RecordingTextOutput())
        let result = try await runner.run(invocation("/bin/echo", ["hello", "world"]), output: .capture)
        #expect(result.status == 0)
        #expect(result.standardOutput == "hello world\n")
        #expect(result.standardError.isEmpty)
    }

    @Test("keeps standard error apart from standard output")
    func separatesStandardError() async throws {
        let runner = ProcessRunner(output: RecordingTextOutput())
        let result = try await runner.run(invocation("/bin/ls", ["/jerd-dev-tests-no-such-path"]), output: .capture)
        #expect(result.status != 0)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("jerd-dev-tests-no-such-path"))
    }

    @Test("passes arguments literally, without a shell")
    func passesArgumentsLiterally() async throws {
        let runner = ProcessRunner(output: RecordingTextOutput())
        let result = try await runner.run(invocation("/bin/echo", ["$HOME", "a;b", "*"]), output: .capture)
        #expect(result.standardOutput == "$HOME a;b *\n")
    }

    @Test("uses exactly the given environment")
    func usesGivenEnvironment() async throws {
        let runner = ProcessRunner(output: RecordingTextOutput())
        var command = invocation("/usr/bin/env", [])
        command.environment = ["ONLY": "this"]
        let result = try await runner.run(command, output: .capture)
        #expect(result.standardOutput == "ONLY=this\n")
    }

    @Test("prints streamed lines to the matching channel")
    func streamsLines() async throws {
        let output = RecordingTextOutput()
        let runner = ProcessRunner(output: output)
        _ = try await runner.run(invocation("/usr/bin/printf", ["one\\ntwo"]), output: .stream)
        #expect(output.standardOutput == "one\ntwo\n")
    }

    @Test("prints only the lines that the filter accepts, and still captures all")
    func streamsMatchingLines() async throws {
        let output = RecordingTextOutput()
        let runner = ProcessRunner(output: output)
        let mode = OutputMode.streamMatching { $0.contains("warning:") }
        let result = try await runner.run(invocation("/usr/bin/printf", ["a\\nwarning: b\\nc\\n"]), output: mode)
        #expect(output.standardOutput == "warning: b\n")
        #expect(result.standardOutput == "a\nwarning: b\nc\n")
    }

    @Test("stops a command at its time limit and keeps its output")
    func stopsAtTimeLimit() async throws {
        let runner = ProcessRunner(output: RecordingTextOutput(), killDelay: .seconds(1), groups: ChildProcessGroups())
        let command = invocation("/bin/sleep", ["30"], timeout: .milliseconds(200))
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await runner.run(command, output: .capture)
        #expect(result.exceededTimeLimit == .milliseconds(200))
        #expect(result.status == 128 + SIGTERM)
        #expect(throws: InvocationFailure.timedOut(commandLine: "/bin/sleep 30", limit: .milliseconds(200))) {
            try result.checked()
        }
        #expect(start.duration(to: clock.now) < .seconds(10))
    }

    @Test("reports a missing executable as a launch failure")
    func reportsLaunchFailure() async throws {
        let runner = ProcessRunner(output: RecordingTextOutput())
        do {
            _ = try await runner.run(invocation("/jerd-dev-tests/missing", []), output: .capture)
            Issue.record("The run must fail.")
        } catch let failure as InvocationFailure {
            guard case .launchFailed(let commandLine, _) = failure else {
                Issue.record("Unexpected failure: \(failure)")
                return
            }
            #expect(commandLine == "/jerd-dev-tests/missing")
        }
    }

    @Test("finishes promptly when output closes with the exit")
    func finishesPromptly() async throws {
        let runner = ProcessRunner(output: RecordingTextOutput(), drainLimit: .seconds(20))
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await runner.run(invocation("/usr/bin/true", []), output: .capture)
        #expect(start.duration(to: clock.now) < .seconds(5))
    }
}

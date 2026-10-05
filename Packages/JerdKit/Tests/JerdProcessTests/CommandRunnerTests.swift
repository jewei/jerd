import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct CommandRunnerTests {
    private func runner(_ folder: TemporaryDirectory) throws -> CommandRunner {
        try OwnedDirectory.create(folder.path("tmp"))
        return CommandRunner(temporaryRoot: folder.path("tmp"))
    }

    @Test func aNonZeroStatusIsAResultNotAnError() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/false"), workingDirectory: folder.url)
        let result = try await runner(folder).run(request, timeout: .seconds(5))
        #expect(result.status == 1)
        #expect(!result.succeeded)
    }

    @Test func aSignalledCommandReportsTheShellStatus() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let sleeper = try await Fixtures.shared.executable("sleeper")
        let request = ProcessRequest(executable: sleeper, arguments: ["signal"], workingDirectory: folder.url)
        #expect(try await runner(folder).run(request, timeout: .seconds(5)).status == 128 + SIGTERM)
    }

    @Test func aTimeoutStopsTheCommandAndLeavesNoFileInEitherFolder() async throws {
        let folder = try TemporaryDirectory(" command timeout")
        defer { folder.remove() }
        let work = folder.path("work")
        try OwnedDirectory.create(work)
        let sleeper = try await Fixtures.shared.executable("sleeper")
        let request = ProcessRequest(executable: sleeper, arguments: ["ignore-term"], workingDirectory: work)
        try OwnedDirectory.create(folder.path("tmp"))
        let quick = CommandRunner(
            temporaryRoot: folder.path("tmp"),
            cleanupPolicy: .forceful(leaderTimeout: .milliseconds(50), groupTimeout: .milliseconds(50)))
        let error = try await #require(throws: JerdError.self) {
            try await quick.run(request, timeout: .milliseconds(500))
        }
        #expect(error.kind == .timedOut)
        #expect(error.message.hasPrefix("Command timed out: \(sleeper.path)\n"))
        let pid = try #require(await waitForPID(in: work.appendingPathComponent("sleeper.pid")))
        #expect(isGone(pid))
        #expect(try FileManager.default.contentsOfDirectory(atPath: work.path) == ["sleeper.pid"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path("tmp").path).isEmpty)
    }

    @Test func cancellationStopsTheCommandAndThrows() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let sleeper = try await Fixtures.shared.executable("sleeper")
        let request = ProcessRequest(executable: sleeper, workingDirectory: folder.url)
        let commands = try runner(folder)
        let task = Task { try await commands.run(request, timeout: .seconds(20)) }
        let pid = try #require(await waitForPID(in: folder.path("sleeper.pid")))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(isGone(pid))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path("tmp").path).isEmpty)
    }

    @Test func largeOutputKeepsTheFirstMebibyteAndTheActualTail() async throws {
        let folder = try TemporaryDirectory(" command tail")
        defer { folder.remove() }
        let binary = try await Fixtures.shared.executable("large-output")
        let request = ProcessRequest(executable: binary, workingDirectory: folder.url)
        let result = try await runner(folder).run(request, timeout: .seconds(10))
        #expect(result.status == 7)
        #expect(result.output.hasPrefix("first-output"))
        #expect(result.output.utf8.count == CommandRunner.outputLimit)
        #expect(!result.output.contains("last-failure-detail"))
        #expect(result.diagnosticOutput.hasSuffix("last-failure-detail\n"))
        #expect(result.diagnosticOutput.utf8.count == CommandRunner.diagnosticLimit)
    }

    @Test func aReadOnlyWorkingFolderWorksBecauseOutputIsKeptElsewhere() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/bin/pwd"), workingDirectory: URL(fileURLWithPath: "/"))
        let result = try await runner(folder).run(request, timeout: .seconds(5))
        #expect(result.output == "/\n")
    }

    @Test func redactedOutputAndDiagnosticsHideTheSecret() async throws {
        let folder = try TemporaryDirectory(" redacted-command")
        defer { folder.remove() }
        let secret = "another-test-credential"
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/printenv"), arguments: ["TEST_CREDENTIAL"],
            workingDirectory: folder.url, environment: ["TEST_CREDENTIAL": secret], redactedValues: [secret])
        let result = try await runner(folder).run(request, timeout: .seconds(5))
        #expect(result.status == 0)
        #expect(result.output == "[redacted]\n")
        #expect(!result.diagnosticOutput.contains(secret))
    }

    @Test func aMissingExecutableIsAProcessFailure() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let request = ProcessRequest(executable: URL(fileURLWithPath: "/missing/tool"), workingDirectory: folder.url)
        await #expect(throws: JerdError.processFailed("Executable is missing or is not executable: /missing/tool")) {
            try await runner(folder).run(request, timeout: .seconds(5))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path("tmp").path).isEmpty)
    }
}

import Foundation
import Testing

@testable import JerdDevKit

/// Steps with a recording runner: they plan the right commands and report results, and no process starts.
@Suite("Steps")
struct StepTests {
    @Test("JerdKit tests run without inherited JERD_ variables")
    func kitTestsStripEnvironment() async throws {
        let runner = RecordingProcessRunner()
        let context = TestFixtures.context(
            runner: runner, environment: ["PATH": "/usr/bin", "JERD_PHP_CLI": "/r/php"])
        try await TestStep.kit(context, testTargets: ["JerdWebTests"], filter: nil, groups: [])
        #expect(runner.recorded.count == 1)
        #expect(runner.recorded.first?.environment == ["PATH": "/usr/bin"])
    }

    @Test("failed tests fail the step with the exit status")
    func failedTestsFail() async {
        let runner = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 1) }
        let context = TestFixtures.context(runner: runner)
        await #expect(throws: DevFailure.checkFailed("Tools tests failed with exit status 1.")) {
            try await TestStep.tools(context, filter: nil)
        }
    }

    /// A temporary repository with a built Debug app whose Info.plist has `plist`.
    private func repositoryWithBuiltApp(plist: Data) throws -> Repository {
        let repository = Repository(root: try TestFixtures.temporaryFolder())
        let app = BuildPlan.appURL(repository: repository, configuration: .debug)
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try plist.write(to: contents.appending(path: "Info.plist"))
        return repository
    }

    @Test("a build checks the built app and prints the app path at the end")
    func buildPrintsAppPath() async throws {
        let repository = try repositoryWithBuiltApp(plist: try BuiltAppPolicyTests.validPlist())
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let runner = RecordingProcessRunner { invocation in
            InvocationResult(commandLine: invocation.commandLine, status: 0, standardOutput: "arm64\n")
        }
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: repository, runner: runner, output: output)
        try await BuildStep.run(context, options: BuildOptions())
        #expect(output.standardOutput.hasSuffix("    .build/xcode/Build/Products/Debug/Jerd.app\n"))
        #expect(output.standardOutput.contains("ok: Jerd, JerdCLI, and JerdHelper contain only arm64."))
        let lipoCalls = runner.recorded.filter { $0.executable.path == "/usr/bin/lipo" }
        #expect(
            lipoCalls.map(\.arguments.last)
                == BuiltAppPolicy.executables.map {
                    BuildPlan.appURL(repository: repository, configuration: .debug).appending(path: $0).path
                })
    }

    @Test("a build fails when the built app has a changed feed URL or a universal executable")
    func buildChecksBuiltApp() async throws {
        let plist = try BuiltAppPolicyTests.validPlist(changing: ["SUFeedURL": "https://evil.example/a.xml"])
        let repository = try repositoryWithBuiltApp(plist: plist)
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let runner = RecordingProcessRunner { invocation in
            InvocationResult(commandLine: invocation.commandLine, status: 0, standardOutput: "x86_64 arm64\n")
        }
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: repository, runner: runner, output: output)
        await #expect(throws: DevFailure.checkFailed("The built app does not have the required settings.")) {
            try await BuildStep.run(context, options: BuildOptions())
        }
        #expect(output.standardError.contains("SUFeedURL has string \"https://evil.example/a.xml\""))
        #expect(output.standardError.contains("contains x86_64 arm64; it must contain only arm64."))
    }

    @Test("a failed quiet build writes the full log and prints its last lines")
    func failedBuildWritesLog() async throws {
        let repository = Repository(root: try TestFixtures.temporaryFolder())
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let runner = RecordingProcessRunner { invocation in
            InvocationResult(
                commandLine: invocation.commandLine, status: 65,
                standardOutput: "Undefined symbols for architecture arm64:\n  referenced from: main")
        }
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: repository, runner: runner, output: output)
        await #expect(throws: DevFailure.checkFailed("The Debug build failed with exit status 65.")) {
            try await BuildStep.run(context, options: BuildOptions())
        }
        let log = try String(contentsOf: repository.logs.appending(path: "debug-build.log"), encoding: .utf8)
        #expect(log.contains("Result: failed with exit status 65"))
        #expect(log.contains("Undefined symbols for architecture arm64:"))
        #expect(output.standardOutput.contains("The full log is in .build/logs/debug-build.log."))
        #expect(output.standardOutput.contains("      referenced from: main"))
    }

    @Test("a check build without runtimes warns that it must never ship")
    func releaseWithoutRuntimesWarns() async throws {
        let repository = Repository(root: try TestFixtures.temporaryFolder())
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let runner = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 65) }
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: repository, runner: runner, output: output)
        let options = BuildOptions(configuration: .release, allowsMissingRuntimes: true)
        await #expect(throws: DevFailure.self) { try await BuildStep.run(context, options: options) }
        #expect(output.standardOutput.contains("warning: Runtime payloads are not required."))
        #expect(runner.recorded.first?.arguments.contains("JERD_REQUIRE_RUNTIMES=NO") == true)
    }

    @Test("a snapshot renderer usage refusal is a usage error, and a time-out is a failed check")
    func snapshotExitStatuses() async {
        let refused = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 64) }
        await #expect(
            throws: DevFailure.usage("The snapshot renderer refused the arguments. See its message above.")
        ) {
            try await SnapshotStep.run(TestFixtures.context(runner: refused), pages: ["nope"])
        }
        let timedOut = RecordingProcessRunner {
            InvocationResult(commandLine: $0.commandLine, status: 143, exceededTimeLimit: .seconds(5))
        }
        await #expect(
            throws: DevFailure.checkFailed("The snapshot renderer stopped at the time limit of 5 s.")
        ) {
            try await SnapshotStep.run(TestFixtures.context(runner: timedOut), pages: [])
        }
    }

    @Test("the format check reports a missing swift-format as a missing prerequisite")
    func formatNeedsSwiftFormat() async {
        let runner = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 72) }
        let context = TestFixtures.context(runner: runner)
        await #expect(throws: DevFailure.missingPrerequisite(Prerequisite.swiftFormat.missingMessage)) {
            try await FormatStep.check(context)
        }
        #expect(runner.recorded.map(\.arguments) == [["--find", "swift-format"]])
    }

    @Test("the format check fails on findings and tells how to fix them")
    func formatCheckFails() async {
        let runner = RecordingProcessRunner { invocation in
            InvocationResult(commandLine: invocation.commandLine, status: invocation.arguments[0] == "--find" ? 0 : 1)
        }
        let context = TestFixtures.context(runner: runner)
        await #expect(
            throws: DevFailure.checkFailed(
                "swift-format found the problems above. Run ./dev format, then fix the rest.")
        ) {
            try await FormatStep.check(context)
        }
    }

    @Test("project generation needs XcodeGen")
    func generateNeedsXcodeGen() async {
        var toolchain = TestFixtures.toolchain
        toolchain.xcodegen = nil
        let context = TestFixtures.context(toolchain: toolchain)
        await #expect(throws: DevFailure.missingPrerequisite(Prerequisite.xcodeGen.missingMessage)) {
            try await GenerateStep.check(context)
        }
    }

    @Test("doctor reports every program and fails only for a missing required one")
    func doctorReports() async {
        let runner = RecordingProcessRunner { invocation in
            let output = invocation.arguments == ["-version"] ? "Xcode 27.0\n" : "Apple Swift version 6.4\n"
            return InvocationResult(commandLine: invocation.commandLine, status: 0, standardOutput: output)
        }
        var toolchain = TestFixtures.toolchain
        toolchain.xcodegen = nil
        let context = TestFixtures.context(toolchain: toolchain, runner: runner)
        let findings = await DoctorStep.findings(context)
        #expect(findings.map(\.prerequisite) == [.xcode, .swift, .swiftFormat, .xcodeGen, .gitHubCLI])
        #expect(findings.map(\.level) == [.warning, .ok, .ok, .missing, .information])
        #expect(DoctorEvaluation.exitStatus(of: findings) == .missingPrerequisite)
    }
}

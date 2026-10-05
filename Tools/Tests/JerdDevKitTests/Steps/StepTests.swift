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

    @Test("a build prints the app path at the end")
    func buildPrintsAppPath() async throws {
        let output = RecordingTextOutput()
        let context = TestFixtures.context(output: output)
        try await BuildStep.run(context, options: BuildOptions())
        #expect(output.standardOutput.hasSuffix("    .build/xcode/Build/Products/Debug/Jerd.app\n"))
    }

    @Test("a failed quiet build points to the verbose log")
    func failedBuildHint() async {
        let runner = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 65) }
        let context = TestFixtures.context(runner: runner)
        await #expect(
            throws: DevFailure.checkFailed("The Debug build failed. Run ./dev build --verbose for the full log.")
        ) {
            try await BuildStep.run(context, options: BuildOptions())
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

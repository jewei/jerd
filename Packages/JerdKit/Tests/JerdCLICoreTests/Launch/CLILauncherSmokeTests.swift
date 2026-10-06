import Foundation
import Testing

@testable import JerdCLICore

/// Runs the launcher logic against a fake PHP script, and runs its plan as `execv` would.
@Suite struct CLILauncherSmokeTests {
    @Test func plannedCommandRunsWithItsArgumentsEnvironmentAndExitStatus() throws {
        let fixture = try CLIFixture()
        defer { fixture.remove() }
        let php = try fixture.installPHP("8.5")
        try fixture.saveDefault(php)
        let companions = try fixture.installCompanions()
        let environment = ["PATH": "/usr/bin:/bin", "HOME": fixture.home.path]
        let image = RecordingProcessImage()
        let launcher = CLILauncher(
            layout: fixture.layout, caBundles: FakeCABundles(.success(nil)), processImage: image,
            diagnostics: RecordingDiagnostics())
        let status = launcher.run(
            CLIInvocation(
                arguments: ["composer", "require", "a b/c"], environment: environment, workingDirectory: "/"))
        #expect(status == CLILauncher.failureStatus)
        let plan = try #require(image.recorded.first)

        let (output, exitStatus) = try execute(plan, environment: environment)
        let bin = fixture.layout.binDirectory.path
        #expect(exitStatus == 7)
        #expect(
            output == """
                arg=\(php.cliPath)
                arg=-c
                arg=\(fixture.layout.runtimes.cliINIFile.path)
                arg=\(companions.composerPath)
                arg=require
                arg=a b/c
                PATH=\(bin):/usr/bin:/bin
                SCAN=\(fixture.layout.runtimes.cliEmptyINIDirectory.path)

                """)
    }

    /// Runs the plan in a child: the plan's argument vector and the launcher's changed environment.
    private func execute(_ plan: CLILaunchPlan, environment: [String: String]) throws -> (String, Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executable)
        process.arguments = Array(plan.arguments.dropFirst())
        process.environment = plan.environment(applyingTo: environment)
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }
}

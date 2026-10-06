import Foundation
import Testing

@testable import JerdDevKit

@Suite("Signed XPC check")
struct XPCCheckTests {
    private func result(_ output: String, status: Int32 = 0) -> InvocationResult {
        InvocationResult(commandLine: "swift test", status: status, standardOutput: output)
    }

    @Test("Runs only the JerdXPCCheck test with the identity and without inherited JERD_* values")
    func plansTheTest() {
        let invocation = XPCCheckPlan.invocation(
            repository: TestFixtures.repository, toolchain: TestFixtures.toolchain, identity: "Developer ID",
            inherited: ["PATH": "/usr/bin", "JERD_PHP_CLI": "/x", "JERD_XPC_IDENTITY": "other"])
        #expect(invocation.executable.path == "/usr/bin/xcrun")
        #expect(
            invocation.arguments == [
                "swift", "test", "--package-path", "/work/jerd/Packages/JerdKit", "--filter", "JerdXPCCheck",
            ])
        #expect(invocation.environment == ["PATH": "/usr/bin", "JERD_XPC_IDENTITY": "Developer ID"])
    }

    @Test("Passes when every test of the check ran and passed")
    func passes() {
        let output = """
            ✔ Test "signed XPC transfers both sockets" passed after 0.3 seconds.
            ✔ Test "an unsigned client is refused" passed after 0.1 seconds.
            ✔ Test run with 2 tests in 1 suite passed after 0.4 seconds.
            """
        let evaluation = XPCCheckPlan.evaluate(result(output))
        #expect(evaluation.failure == nil)
        #expect(
            evaluation.cases.map(\.name) == [
                #""signed XPC transfers both sockets""#, #""an unsigned client is refused""#,
            ])
    }

    @Test("Fails when no test ran, when a test was skipped, or when a test failed")
    func refusesRunsThatProveNothing() {
        let none = XPCCheckPlan.evaluate(result("warning: No matching test cases were run"))
        #expect(none.failure?.contains("No JerdXPCCheck test ran") == true)
        let empty = XPCCheckPlan.evaluate(result("✔ Test run with 0 tests in 0 suites passed after 0.0 seconds."))
        #expect(empty.failure != nil && empty.cases.isEmpty)
        let skipped = XPCCheckPlan.evaluate(result("➜ Test xpcCheck() skipped: \"Set JERD_XPC_IDENTITY.\""))
        #expect(skipped.failure?.contains("skipped") == true)
        let failed = XPCCheckPlan.evaluate(result("✘ Test xpcCheck() failed after 0.2 seconds.", status: 1))
        #expect(failed.failure?.contains("failed with exit status 1") == true)
        #expect(failed.cases == [.init(name: "xpcCheck()", passed: false, detail: "failed")])
    }

    @Test("Writes a failed evidence record when the test is missing")
    func recordsAMissingTest() async throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingProcessRunner { invocation in
            let output = invocation.arguments.contains("--filter") ? "warning: No matching test cases were run" : ""
            return InvocationResult(commandLine: invocation.commandLine, status: 0, standardOutput: output)
        }
        let context = TestFixtures.context(repository: Repository(root: root), runner: runner)
        await #expect(throws: DevFailure.self) {
            try await XPCCheckStep.run(context, identity: "ID", clock: FakeHarnessClock())
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: ".build/evidence").path)
        #expect(files == ["2026-10-06T091500Z-xpc.json"])
    }
}

import Foundation
import Testing

@testable import JerdDevKit

@Suite("Test plan")
struct TestPlanTests {
    private let available = ["JerdFoundationTests", "JerdWebTests", "JerdUITests"]

    @Test("accepts target names with and without the Tests suffix, once each")
    func normalizesTargetNames() throws {
        let targets = try TestPlan.testTargets(
            for: ["JerdWeb", "JerdFoundationTests", "JerdWebTests"], available: available)
        #expect(targets == ["JerdWebTests", "JerdFoundationTests"])
    }

    @Test("refuses an unknown target with a usage error that lists the valid names")
    func refusesUnknownTarget() {
        #expect(
            throws: DevFailure.usage("Unknown test target \"JerdNope\". Use one of: JerdFoundation, JerdUI, JerdWeb.")
        ) {
            try TestPlan.testTargets(for: ["JerdNope"], available: available)
        }
    }

    @Test("gives each target one anchored filter")
    func filtersEachTarget() {
        let arguments = TestPlan.filterArguments(testTargets: ["JerdWebTests", "JerdUITests"], filter: nil)
        #expect(arguments == ["--filter", "^JerdWebTests\\.", "--filter", "^JerdUITests\\."])
    }

    @Test("narrows each target filter with the user filter")
    func combinesUserFilter() {
        let arguments = TestPlan.filterArguments(testTargets: ["JerdWebTests"], filter: "routes")
        #expect(arguments == ["--filter", "^JerdWebTests\\..*(?:routes)"])
    }

    @Test("uses the user filter alone without targets, and no filter by default")
    func userFilterAlone() {
        #expect(TestPlan.filterArguments(testTargets: [], filter: "x") == ["--filter", "x"])
        #expect(TestPlan.filterArguments(testTargets: [], filter: nil).isEmpty)
    }

    @Test("runs swift test on JerdKit with the given environment")
    func plansKitTests() {
        let invocation = TestPlan.kitTests(
            repository: TestFixtures.repository, toolchain: TestFixtures.toolchain,
            testTargets: ["JerdWebTests"], filter: nil, environment: ["PATH": "/usr/bin"])
        #expect(invocation.executable.path == "/usr/bin/xcrun")
        #expect(
            invocation.arguments == [
                "swift", "test", "--package-path", "/work/jerd/Packages/JerdKit", "--filter", "^JerdWebTests\\.",
            ])
        #expect(invocation.environment == ["PATH": "/usr/bin"])
        #expect(invocation.timeout == TimeLimit.test)
    }

    @Test(
        "a quiet test run shows failures, diagnostics, and the final count",
        arguments: [
            ("✘ Test \"rule\" recorded an issue at A.swift:3:1: Expectation failed", true),
            ("/a/B.swift:3:1: error: cannot find 'x' in scope", true),
            ("✔ Test run with 12 tests in 3 suites passed after 0.2 seconds.", true),
            ("warning: No matching test cases were run", true),
            ("◇ Test \"rule\" started.", false),
            ("↳ Testing Library Version: 2084", false),
            ("✔ Test \"rule\" passed after 0.001 seconds.", false),
            ("✔ Suite \"Rules\" passed after 0.001 seconds.", false),
            ("[12/300] Compiling JerdWeb Site.swift", false),
            ("Building for debugging...", false),
            ("Build complete! (7.75 sec)", false),
            ("Test Suite 'All tests' started at 2026-10-05 22:18:02.085.", false),
            ("\t Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.006) seconds", false),
            ("Test Case '-[JerdWebTests.Rules testA]' failed (0.1 seconds).", true),
        ])
    func filtersQuietTestOutput(line: String, shown: Bool) {
        #expect(TestPlan.showsInQuietMode(line) == shown)
    }

    @Test("recognizes SwiftPM progress lines and nothing else")
    func recognizesProgress() {
        #expect(SwiftPMOutput.isProgress("[Computing dependencies]"))
        #expect(SwiftPMOutput.isProgress("[3/9] Linking jerd-snapshots"))
        #expect(SwiftPMOutput.isProgress("Building for debugging..."))
        #expect(!SwiftPMOutput.isProgress("/a/B.swift:3:1: error: x"))
        #expect(!SwiftPMOutput.isProgress("[unterminated"))
    }

    @Test("runs swift test on the Tools package")
    func plansToolTests() {
        let invocation = TestPlan.toolTests(
            repository: TestFixtures.repository, toolchain: TestFixtures.toolchain, filter: nil, environment: [:])
        #expect(invocation.arguments == ["swift", "test", "--package-path", "/work/jerd/Tools"])
    }
}

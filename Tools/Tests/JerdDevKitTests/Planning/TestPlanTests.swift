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

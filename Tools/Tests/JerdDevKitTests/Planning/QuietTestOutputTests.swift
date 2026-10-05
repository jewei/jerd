import Testing

@testable import JerdDevKit

@Suite("Quiet test output")
struct QuietTestOutputTests {
    /// The lines that a fresh filter shows from `lines`, in order.
    private func shown(_ lines: [String]) -> [String] {
        var filter = QuietTestOutput()
        return lines.filter { filter.shows($0) }
    }

    @Test(
        "shows failures, diagnostics, and the final count, and hides progress and passed tests",
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
    func filtersSingleLines(line: String, isShown: Bool) {
        #expect(shown([line]) == (isShown ? [line] : []))
    }

    /// Real `swift test` output of a failed parameterized expectation with a comment. One argument
    /// has a line break, so two events span two lines.
    static let failedRun = [
        "◇ Test run started.",
        "↳ Testing Library Version: 2084",
        "↳ Target Platform: arm64e-apple-macos14.0",
        "◇ Suite ZZProbe started.",
        "◇ Test \"probe fails\" started.",
        "◇ Test case passing 1 argument value → \"c\" to \"probe fails\" started.",
        "◇ Test case passing 1 argument value → \"a",
        "b\" to \"probe fails\" started.",
        "✘ Test \"probe fails\" recorded an issue with 1 argument value → \"c\" at ZZProbe.swift:7:9: "
            + "Expectation failed: values.count == 4",
        "↳ the review comment explains the failure",
        "↳ values.count == 4 → false",
        "↳   values.count → 3",
        "✘ Test \"probe fails\" recorded an issue with 1 argument value → \"a",
        "b\" at ZZProbe.swift:7:9: Expectation failed: values.count == 4",
        "↳ the review comment explains the failure",
        "↳ values.count == 4 → false",
        "↳   values.count → 3",
        "✘ Test \"probe fails\" with 2 test cases failed after 0.001 seconds with 2 issues.",
        "✔ Test \"other\" passed after 0.001 seconds.",
        "↳ not a failure detail",
        "✘ Test run with 1 test in 1 suite failed after 0.001 seconds with 2 issues.",
    ]

    @Test("shows the comment and the values of a failed expectation")
    func showsFailureDetails() {
        let lines = shown(Self.failedRun)
        #expect(lines.filter { $0 == "↳ the review comment explains the failure" }.count == 2)
        #expect(lines.filter { $0 == "↳   values.count → 3" }.count == 2)
        #expect(!lines.contains("↳ Testing Library Version: 2084"))
        #expect(!lines.contains("↳ not a failure detail"))
    }

    @Test("hides every line of a multi-line started event, and keeps the lines of a multi-line failure")
    func handlesMultiLineEvents() {
        let lines = shown(Self.failedRun)
        #expect(!lines.contains("b\" to \"probe fails\" started."))
        #expect(lines.contains("b\" at ZZProbe.swift:7:9: Expectation failed: values.count == 4"))
        #expect(lines.allSatisfy { !$0.hasPrefix("◇ ") })
        #expect(lines.last == "✘ Test run with 1 test in 1 suite failed after 0.001 seconds with 2 issues.")
    }
}

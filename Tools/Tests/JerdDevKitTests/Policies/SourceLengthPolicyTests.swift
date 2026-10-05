import Testing

@testable import JerdDevKit

@Suite("Source length policy")
struct SourceLengthPolicyTests {
    /// `⏎` stands for a line break, so that each test case shows on one line in the test log.
    @Test(
        "counts lines as an editor shows them",
        arguments: [("", 0), ("a", 1), ("a⏎", 1), ("a⏎b", 2), ("a⏎b⏎", 2), ("⏎⏎", 2)])
    func countsLines(text: String, count: Int) {
        let text = text.replacingOccurrences(of: "⏎", with: "\n")
        #expect(SourceLengthPolicy.lineCount(of: text) == count)
    }

    @Test("accepts 300 lines and reports 301 lines with the count")
    func reportsLongFiles() {
        let limit = String(repeating: "x\n", count: 300)
        let over = String(repeating: "x\n", count: 301)
        let findings = SourceLengthPolicy.findings(files: [("A.swift", limit), ("B.swift", over)])
        #expect(findings == [PolicyFinding(file: "B.swift", message: "301 lines; the limit is 300.")])
    }
}

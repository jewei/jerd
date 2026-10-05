import Testing

@testable import JerdDevKit

@Suite("Source length policy")
struct SourceLengthPolicyTests {
    @Test(
        "counts lines as an editor shows them",
        arguments: [("", 0), ("a", 1), ("a\n", 1), ("a\nb", 2), ("a\nb\n", 2), ("\n\n", 2)])
    func countsLines(text: String, count: Int) {
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

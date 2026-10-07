import Testing

@testable import JerdDevKit

@Suite("Private reference policy")
struct PrivateReferencePolicyTests {
    /// The test builds each reference from parts, so that this file passes the policy itself.
    private static let spec = "sp" + "ec"
    private static let review = "re" + "view"
    private static let workPackage = "W" + "P"
    private static let item = "(" + "#"

    @Test(
        "refuses a private spec section or review ID, with the file and line",
        arguments: [
            "Quit does not wait (\(spec) F 2.4).",
            "/// Fix of \(spec) E 7.1.3: a 401 line stopped the connector.",
            "// \(spec.capitalized) B 7.1.2: visible files are served.",
            "(\(review) final-domain-r1 M1)",
            "/// \(review.capitalized) web-r1 C1: the route keeps its path info.",
            "/// The sheet blocked Quit (found in the live run of \(workPackage)12).",
            "/// Sparkle shows the Markdown list as written \(item)5).",
            "/// Publication ends when the feed is served \(item)8, #10).",
        ])
    func refusesReferences(line: String) {
        let findings = PrivateReferencePolicy.findings(files: [("A.swift", "first\n\(line)\n")])
        #expect(findings.map(\.file) == ["A.swift:2"])
        #expect(findings.first?.message.hasPrefix("Do not cite a private") == true)
    }

    @Test(
        "accepts rules, ordinary words, and code names",
        arguments: [
            "The \(spec) file of XcodeGen is project.yml.",
            "let \(spec)Version = \"2.10.0\"",
            "Run a \(review) before you merge.",
            "A \(spec) B without a number is a plain word.",
            "See https://github.com/jewei/jerd/issues/8 for the report.",
            "[Setup](#3-setup) and [Rules](#rules) are anchors.",
            "let \(workPackage)ID = 2 // \(workPackage) alone, or \(workPackage)A, is a plain name.",
            "#selector(run), (#line), and #8 without parentheses are not item numbers.",
        ])
    func acceptsText(line: String) {
        #expect(PrivateReferencePolicy.findings(files: [("A.md", line)]).isEmpty)
    }
}

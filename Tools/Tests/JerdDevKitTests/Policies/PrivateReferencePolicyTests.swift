import Testing

@testable import JerdDevKit

@Suite("Private reference policy")
struct PrivateReferencePolicyTests {
    /// The test builds each reference from parts, so that this file passes the policy itself.
    private static let spec = "sp" + "ec"
    private static let review = "re" + "view"

    @Test(
        "refuses a private spec section or review ID, with the file and line",
        arguments: [
            "Quit does not wait (\(spec) F 2.4).",
            "/// Fix of \(spec) E 7.1.3: a 401 line stopped the connector.",
            "// \(spec.capitalized) B 7.1.2: visible files are served.",
            "(\(review) final-domain-r1 M1)",
            "/// \(review.capitalized) web-r1 C1: the route keeps its path info.",
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
        ])
    func acceptsText(line: String) {
        #expect(PrivateReferencePolicy.findings(files: [("A.md", line)]).isEmpty)
    }
}

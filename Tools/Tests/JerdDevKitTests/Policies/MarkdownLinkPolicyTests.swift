import Testing

@testable import JerdDevKit

@Suite("Markdown link policy")
struct MarkdownLinkPolicyTests {
    @Test("finds inline, image, angle-bracket, titled, and reference links")
    func findsLinkForms() {
        let markdown = """
            See [Architecture](Docs/Architecture.md) and ![icon](Design/icon.png "Icon").
            Also [spaced](<Docs/Run tests.md>) and [anchor](Docs/A.md#layers).
            [ref]: Docs/Reference.md
            """
        #expect(
            MarkdownLinkPolicy.localTargets(in: markdown) == [
                "Docs/Architecture.md", "Design/icon.png", "Docs/Run tests.md", "Docs/A.md#layers",
                "Docs/Reference.md",
            ])
    }

    @Test("skips web links, mail links, page anchors, code spans, and fenced code")
    func skipsNonLocalLinks() {
        let markdown = """
            [web](https://example.com) [mail](mailto:a@b.c) [top](#top) `[code](x.md)`
            ```
            [fenced](y.md)
            ```
            ~~~sh
            [tilde](z.md)
            ~~~
            """
        #expect(MarkdownLinkPolicy.localTargets(in: markdown).isEmpty)
    }

    @Test(
        "resolves targets relative to the document",
        arguments: [
            ("Docs/Architecture.md", "Reference.md", "Docs/Reference.md"),
            ("Docs/Architecture.md", "../AGENTS.md", "AGENTS.md"),
            ("AGENTS.md", "./Docs/A.md#x", "Docs/A.md"),
            ("Docs/A.md", "/Tools/README.md", "Tools/README.md"),
            ("AGENTS.md", "Docs/Run%20tests.md", "Docs/Run tests.md"),
        ])
    func resolvesTargets(file: String, target: String, path: String) {
        #expect(MarkdownLinkPolicy.resolve(target, from: file) == path)
    }

    @Test("refuses a target outside the repository")
    func refusesEscapes() {
        #expect(MarkdownLinkPolicy.resolve("../../x.md", from: "Docs/A.md") == nil)
        let findings = MarkdownLinkPolicy.findings(file: "AGENTS.md", markdown: "[x](../x.md)") { _ in true }
        #expect(
            findings == [PolicyFinding(file: "AGENTS.md", message: "The link ../x.md points outside the repository.")])
    }

    @Test("reports each link to a missing file")
    func reportsMissingFiles() {
        let markdown = "[a](Docs/A.md) [b](Docs/B.md)"
        let findings = MarkdownLinkPolicy.findings(file: "README.md", markdown: markdown) { $0 == "Docs/A.md" }
        #expect(findings == [PolicyFinding(file: "README.md", message: "The link Docs/B.md points to a missing file.")])
    }
}

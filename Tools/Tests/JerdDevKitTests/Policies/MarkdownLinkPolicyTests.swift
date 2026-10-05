import Testing

@testable import JerdDevKit

/// An in-memory repository: exact-case paths and the text of its Markdown files.
struct FakeMarkdownFiles: MarkdownLinkTargets {
    var files: [String: String]

    func exists(_ path: String) -> Bool {
        files.keys.contains { $0 == path || $0.hasPrefix(path + "/") }
    }

    func markdown(at path: String) -> String? {
        files[path]
    }
}

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

    @Test("skips web links, mail links, code spans, and fenced code")
    func skipsNonLocalLinks() {
        let markdown = """
            [web](https://example.com) [mail](mailto:a@b.c) [empty](#) `[code](x.md)`
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
            ("Docs/A.md", "#layers", "Docs/A.md"),
        ])
    func resolvesTargets(file: String, target: String, path: String) {
        #expect(MarkdownLinkPolicy.resolve(target, from: file) == path)
    }

    @Test("refuses a target outside the repository")
    func refusesEscapes() {
        #expect(MarkdownLinkPolicy.resolve("../../x.md", from: "Docs/A.md") == nil)
        let findings = MarkdownLinkPolicy.findings(
            file: "AGENTS.md", markdown: "[x](../x.md)", files: FakeMarkdownFiles(files: [:]))
        #expect(
            findings == [PolicyFinding(file: "AGENTS.md", message: "The link ../x.md points outside the repository.")])
    }

    @Test("reports each link to a missing file")
    func reportsMissingFiles() {
        let markdown = "[a](Docs/A.md) [b](Docs/B.md)"
        let files = FakeMarkdownFiles(files: ["Docs/A.md": ""])
        let findings = MarkdownLinkPolicy.findings(file: "README.md", markdown: markdown, files: files)
        #expect(findings == [PolicyFinding(file: "README.md", message: "The link Docs/B.md points to a missing file.")])
    }

    @Test("reports a link whose letter case differs from the file")
    func reportsWrongCase() {
        let files = FakeMarkdownFiles(files: ["Docs/Architecture.md": ""])
        let findings = MarkdownLinkPolicy.findings(
            file: "README.md", markdown: "[a](docs/architecture.md) [b](Docs/Architecture.md) [c](Docs)",
            files: files)
        #expect(findings.map(\.message) == ["The link docs/architecture.md points to a missing file."])
    }

    @Test("checks anchors against the headings of the target and of the document itself")
    func checksAnchors() {
        let target = """
            # Jerd agent guide
            ## Commands
            ## Pinned and coupled files
            ```
            ## Not a heading
            ```
            """
        let files = FakeMarkdownFiles(files: ["AGENTS.md": target, "Tools/README.md": ""])
        let markdown = """
            # Tools
            [a](../AGENTS.md#commands) [b](../AGENTS.md#pinned-and-coupled-files) [c](#tools)
            [d](../AGENTS.md#not-a-heading) [e](#nowhere)
            """
        let findings = MarkdownLinkPolicy.findings(file: "Tools/README.md", markdown: markdown, files: files)
        #expect(
            findings.map(\.message) == [
                "The link ../AGENTS.md#not-a-heading names a missing heading.",
                "The link #nowhere names a missing heading.",
            ])
    }

    @Test(
        "makes anchors as GitHub does",
        arguments: [
            ("Run `./dev check` first", "run-dev-check-first"),
            ("Pinned and coupled files", "pinned-and-coupled-files"),
            ("A [link](x.md) title", "a-link-title"),
            ("snake_case and dashes - here", "snake_case-and-dashes---here"),
            ("Über Größe", "über-größe"),
        ])
    func makesSlugs(heading: String, slug: String) {
        #expect(MarkdownAnchors.slug(heading) == slug)
    }

    @Test("numbers repeated headings and reads HTML anchors")
    func numbersRepeatedHeadings() {
        let anchors = MarkdownAnchors.anchors(in: "## Notes\n## Notes\n<a id=\"custom\"></a>\n### Notes ###")
        #expect(anchors == ["notes", "notes-1", "notes-2", "custom"])
    }
}

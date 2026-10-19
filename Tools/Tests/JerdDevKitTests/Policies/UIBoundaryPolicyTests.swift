import Testing

@testable import JerdDevKit

@Suite("JerdUI boundary policy")
struct UIBoundaryPolicyTests {
    private let domain: [(path: String, text: String)] = [
        ("Packages/JerdKit/Sources/JerdWeb/A.swift", "package actor SiteRegistry {}\nstruct Site {}")
    ]

    @Test("reports an actor of another target and a side-effect API in code")
    func reportsDirectUses() {
        let ui: [(path: String, text: String)] = [
            ("UI.swift", "let a = SiteRegistry()\nlet b = Site()\nlet c = FileManager.default")
        ]
        let findings = UIBoundaryPolicy.findings(uiFiles: ui, otherFiles: domain)
        #expect(
            findings == [
                PolicyFinding(
                    file: "UI.swift",
                    message: "line 1: JerdUI uses `SiteRegistry` directly; call the actor through a port "
                        + "protocol that JerdLive implements."),
                PolicyFinding(
                    file: "UI.swift",
                    message: "line 3: JerdUI uses `FileManager` directly; call the API through a port "
                        + "protocol that JerdLive implements."),
            ])
    }

    @Test("accepts names in comments, strings, and longer identifiers")
    func acceptsTextAndLongerNames() {
        let ui: [(path: String, text: String)] = [
            ("UI.swift", "/// `SiteRegistry`\nText(\"Process Recovery\")\nlet a = ProcessInfo.processInfo")
        ]
        #expect(UIBoundaryPolicy.findings(uiFiles: ui, otherFiles: domain).isEmpty)
    }

    @Test("finds the actor names of a file")
    func findsActorNames() {
        #expect(UIBoundaryPolicy.actorNames(in: "public actor A {}\n// actor B\nfinal actor C: P {}") == ["A", "C"])
    }
}

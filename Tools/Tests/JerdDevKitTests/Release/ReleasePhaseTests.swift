import Testing

@testable import JerdDevKit

@Suite("Release phases")
struct ReleasePhaseTests {
    static let facts = ReleasePhase.Facts(
        tag: "v0.2.0", title: "Jerd 0.2.0", sourceCommit: ReleaseFixtures.commit,
        diskImage: ".build/releases/Jerd-0.2.0-3/Jerd-0.2.0.dmg",
        symbols: ".build/releases/Jerd-0.2.0-3/Jerd-0.2.0-3.dSYMs.zip",
        notes: ".build/releases/Jerd-0.2.0-3/release-notes.md")

    static func text(_ phase: ReleasePhase) -> String { phase.recovery(facts).joined(separator: "\n") }

    @Test("Before the commit, nothing is public and the command can run again")
    func local() {
        #expect(
            Self.text(.local)
                == "Nothing was published, and no tracked file changed. Correct the cause and run the command again.")
    }

    @Test("A local commit or tag is undone with a reset to the source commit")
    func committed() {
        for phase in [ReleasePhase.committing, .committed] {
            #expect(Self.text(phase).contains("Nothing was published."))
            #expect(Self.text(phase).contains("git tag -d v0.2.0; git reset --hard \(ReleaseFixtures.commit)"))
        }
    }

    @Test("A public tag is finished with the exact release command, then the push of main, or cancelled")
    func tagged() {
        let text = Self.text(.tagged)
        #expect(
            text.contains(
                "gh release create v0.2.0 .build/releases/Jerd-0.2.0-3/Jerd-0.2.0.dmg "
                    + ".build/releases/Jerd-0.2.0-3/Jerd-0.2.0-3.dSYMs.zip --repo jewei/jerd --verify-tag "
                    + "--title \"Jerd 0.2.0\" --notes-file .build/releases/Jerd-0.2.0-3/release-notes.md; "
                    + "then git push origin HEAD:main"))
        #expect(text.contains("git push origin :refs/tags/v0.2.0"))
        #expect(text.contains("gh release edit v0.2.0 --draft=false"))
    }

    @Test("A public release without the feed needs only the push of main")
    func released() {
        #expect(Self.text(.released).contains("Push again: git push origin HEAD:main"))
        #expect(Self.text(.released).contains("git pull --no-rebase origin main"))
        #expect(Self.text(.published).isEmpty)
    }
}

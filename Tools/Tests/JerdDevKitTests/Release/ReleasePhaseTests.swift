import Testing

@testable import JerdDevKit

@Suite("Release phases")
struct ReleasePhaseTests {
    static let candidate = "/r/.build/releases/Jerd-0.2.0-3"
    static let facts = ReleasePhase.Facts(
        tag: "v0.2.0", title: "Jerd 0.2.0", sourceCommit: ReleaseFixtures.commit, repositoryRoot: "/r",
        diskImage: "\(candidate)/Jerd-0.2.0.dmg", symbols: "\(candidate)/Jerd-0.2.0-3.dSYMs.zip",
        notes: "\(candidate)/release-notes.md")

    static func text(_ phase: ReleasePhase) -> String { phase.recovery(facts).joined(separator: "\n") }

    @Test("Before the commit, nothing is public and the command can run again")
    func local() {
        #expect(
            Self.text(.local)
                == "Nothing was published, and no tracked file changed. Correct the cause and run the command again.")
    }

    @Test("No phase text discards work: no hard reset, no checkout, no clean, and HEAD moves only with --keep")
    func neverDiscardsWork() {
        for phase in ReleasePhase.allCases {
            let text = Self.text(phase)
            for destructive in ["reset --hard", "git checkout", "git clean", "push --force", "push -f", "stash"] {
                #expect(!text.contains(destructive), "\(phase): \(destructive)")
            }
            for line in phase.recovery(Self.facts) where line.contains("git reset") {
                #expect(line.contains("git reset --keep \(ReleaseFixtures.commit)"), "\(phase): \(line)")
                #expect(line.contains("if git log -1 --format=%s prints \"Release v0.2.0\""), "\(phase): \(line)")
            }
        }
    }

    @Test("Each public phase names the folder, and every gh command names the repository")
    func folderAndRepository() {
        for phase in [ReleasePhase.committing, .committed, .tagged, .released] {
            #expect(phase.recovery(Self.facts)[1] == "Run these commands in /r.")
            for command in Self.text(phase).components(separatedBy: "gh release ").dropFirst() {
                let end = command.firstIndex(where: { $0 == ";" || $0 == "\n" }) ?? command.endIndex
                #expect(command[..<end].contains("--repo jewei/jerd"), "\(phase): gh release \(command[..<end])")
            }
        }
    }

    @Test("During the commit, only the three release files are restored to the source commit")
    func committing() {
        let text = Self.text(.committing)
        #expect(text.contains("Nothing was published."))
        #expect(
            text.contains(
                "git restore --source=\(ReleaseFixtures.commit) --staged --worktree -- "
                    + "Configuration/Version.xcconfig CHANGELOG.md appcast.xml"))
        #expect(text.contains("git tag -d v0.2.0 (if it exists)"))
    }

    @Test("A local commit and tag are undone, and a public tag points to the next text")
    func committed() {
        let text = Self.text(.committed)
        #expect(text.contains("git tag -d v0.2.0; if git log -1"))
        #expect(text.contains("failed \"Publish the GitHub release\" step (Recovery in Tools/README.md)"))
    }

    @Test("A public tag covers no release, a draft, a public release, and a cancel that removes a draft")
    func tagged() {
        let text = Self.text(.tagged)
        #expect(
            text.contains(
                "No release: gh release create v0.2.0 \(Self.candidate)/Jerd-0.2.0.dmg "
                    + "\(Self.candidate)/Jerd-0.2.0-3.dSYMs.zip --repo jewei/jerd --verify-tag "
                    + "--title \"Jerd 0.2.0\" --notes-file \(Self.candidate)/release-notes.md; "
                    + "then git push origin HEAD:main"))
        #expect(text.contains("gh release edit v0.2.0 --repo jewei/jerd --draft=false"))
        #expect(text.contains("A public release with both assets: git push origin HEAD:main"))
        #expect(text.contains("gh release delete v0.2.0 --repo jewei/jerd --yes"))
        #expect(text.contains("git push origin :refs/tags/v0.2.0"))
    }

    @Test("A public release without the feed needs the asset upload or only the push of main")
    func released() {
        let text = Self.text(.released)
        #expect(text.contains("Then publish the feed: git push origin HEAD:main"))
        #expect(text.contains("--repo jewei/jerd --clobber"))
        #expect(text.contains("git pull --no-rebase origin main. A conflict in CHANGELOG.md"))
        #expect(Self.text(.published).isEmpty)
    }
}

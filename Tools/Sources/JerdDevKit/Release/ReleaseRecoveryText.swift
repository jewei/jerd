/// The recovery lines of each public phase of a release. Pure. Every `gh` command names the
/// repository, every path is absolute, and the first line names the folder to run the commands in.
struct ReleaseRecoveryText: Sendable {
    let facts: ReleasePhase.Facts

    private var tag: String { facts.tag }
    private var repo: String { "--repo \(ReleaseNames.repository)" }
    private var runIn: String { "Run these commands in \(facts.repositoryRoot)." }
    private var pushMain: String { "git push origin HEAD:\(ReleaseNames.mainBranch)" }
    private var files: String { ReleaseCommitFiles.paths.joined(separator: " ") }
    private var lastIsRelease: String {
        "if git log -1 --format=%s prints \"\(ReleaseNames.commitMessage(tag: facts.tag))\""
    }
    private var resetRelease: String { "git reset --keep \(facts.sourceCommit)" }
    private var upload: String { "gh release upload \(tag) \(facts.diskImage) \(facts.symbols) \(repo) --clobber" }

    /// Undoes the release commit and tag: the tag did not exist before, and `--keep` keeps every edit.
    private var undoCommit: String {
        "git tag -d \(tag); \(lastIsRelease), \(resetRelease)"
    }

    var committing: [String] {
        [
            "Nothing was published. The release changed \(files), and maybe made the release commit and the "
                + "tag \(tag), only on this Mac.",
            runIn,
            "Undo only these changes: git tag -d \(tag) (if it exists); \(lastIsRelease), \(resetRelease); "
                + "then git restore --source=\(facts.sourceCommit) --staged --worktree -- \(files)",
            "Then run the command again.",
        ]
    }

    var committed: [String] {
        [
            "Nothing was published. The release commit and the tag \(tag) exist only on this Mac.",
            runIn,
            "If git ls-remote --tags origin \(tag) prints a line, the tag is on GitHub: follow the text for a "
                + "failed \"\(ReleasePublication.Title.createRelease)\" step (Recovery in Tools/README.md).",
            "Otherwise undo the commit and the tag, then run the command again: \(undoCommit)",
        ]
    }

    var tagged: [String] {
        let create =
            "gh release create \(tag) \(facts.diskImage) \(facts.symbols) \(repo) --verify-tag "
            + "--title \"\(facts.title)\" --notes-file \(facts.notes)"
        return [
            "The tag \(tag) is on GitHub. The feed is not, so installed apps see nothing.",
            runIn,
            "See what GitHub has: gh release view \(tag) \(repo) --json isDraft,assets",
            "No release: \(create); then \(pushMain)",
            "A draft: \(upload); gh release edit \(tag) \(repo) --draft=false; then \(pushMain)",
            "A public release with both assets: \(pushMain)",
            "To cancel instead: gh release delete \(tag) \(repo) --yes (if a release or draft exists); "
                + "git push origin :refs/tags/\(tag); \(undoCommit)",
        ]
    }

    var released: [String] {
        [
            "The GitHub release \(tag) is public, but the feed is not. Installed apps see nothing yet.",
            runIn,
            "If \"\(ReleasePublication.Title.checkAssets)\" failed, upload the files again and compare them: "
                + "\(upload); gh release view \(tag) \(repo) --json assets",
            "Then publish the feed: \(pushMain)",
            "If main moved: git pull --no-rebase origin main. A conflict in CHANGELOG.md comes from new notes "
                + "under ## [Unreleased]: keep the section of \(tag.dropFirst()) and put the new notes under "
                + "## [Unreleased] above it. Check that the new item is the first item in appcast.xml, then \(pushMain)",
        ]
    }
}

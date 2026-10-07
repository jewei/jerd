/// How far a release got, so a failure can say what is public and how to recover. The public steps
/// run in this order: the tag, then the GitHub release with the disk image, then `main` with the feed.
/// Installed apps read the feed from `main`, so they never see an item whose disk image does not exist.
enum ReleasePhase: String, CaseIterable, Sendable {
    /// Only the candidate folder changed. Nothing is public.
    case local
    /// The release commit is being made: tracked files, and maybe a local commit, changed.
    case committing
    /// The release commit and the tag exist only on this Mac.
    case committed
    /// The tag is on GitHub. The release and the feed are not.
    case tagged
    /// The GitHub release is public. The feed is not.
    case released
    /// The feed is on `main`. The release is complete.
    case published

    /// The facts that the recovery commands name. Paths are relative to the repository.
    struct Facts: Equatable, Sendable {
        var tag: String
        var title: String
        var sourceCommit: String
        var diskImage: String
        var symbols: String
        var notes: String
    }

    /// What is public after a failure in this phase, and the exact commands that finish or undo it.
    func recovery(_ facts: Facts) -> [String] {
        let reset = "git tag -d \(facts.tag); git reset --hard \(facts.sourceCommit)"
        let pushMain = "git push origin HEAD:main"
        let create =
            "gh release create \(facts.tag) \(facts.diskImage) \(facts.symbols) --repo \(ReleaseNames.repository) "
            + "--verify-tag --title \"\(facts.title)\" --notes-file \(facts.notes)"
        switch self {
        case .local:
            return ["Nothing was published, and no tracked file changed. Correct the cause and run the command again."]
        case .committing, .committed:
            return [
                "Nothing was published. The release changes, and maybe the release commit and the tag \(facts.tag), "
                    + "exist only on this Mac.",
                "If git ls-remote --tags origin \(facts.tag) prints a line, the tag is on GitHub: "
                    + "follow the steps for a public tag in Tools/README.md.",
                "Otherwise undo the local changes, then run the command again: \(reset)",
            ]
        case .tagged:
            return [
                "The tag \(facts.tag) is on GitHub. The release and the feed are not, so installed apps see nothing.",
                "Check for a draft: gh release view \(facts.tag) --repo \(ReleaseNames.repository) --json isDraft,assets",
                "If no release exists, finish by hand: \(create); then \(pushMain)",
                "If a draft exists, upload what is missing with gh release upload \(facts.tag) <files> --clobber, "
                    + "publish it with gh release edit \(facts.tag) --draft=false, then \(pushMain)",
                "To cancel instead: git push origin :refs/tags/\(facts.tag); \(reset)",
            ]
        case .released:
            return [
                "The GitHub release \(facts.tag) is public, but the feed is not. This is safe. Push again: \(pushMain)",
                "If main moved: git pull --no-rebase origin main, check that the new item is the first item "
                    + "in appcast.xml, then \(pushMain)",
            ]
        case .published:
            return []
        }
    }
}

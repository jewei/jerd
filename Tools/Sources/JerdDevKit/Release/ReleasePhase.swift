/// How far a release got, so a failure can say what is public and how to recover. The public steps
/// run in this order: the tag, then the GitHub release with the disk image, then `main` with the feed.
/// Installed apps read the feed from `main`, so they never see an item whose disk image does not exist.
///
/// Each recovery text undoes only what the release did. It never discards edits that are not
/// committed or commits of the user: it restores only the three release files, and it moves HEAD only
/// with `git reset --keep` and only from the release commit.
enum ReleasePhase: String, CaseIterable, Sendable {
    /// Only the candidate folder changed. Nothing is public.
    case local
    /// The release commit is being made: the three release files, and maybe a local commit and tag, changed.
    case committing
    /// The release commit and the tag exist only on this Mac.
    case committed
    /// The tag is on GitHub. The release may be missing, a draft, or public. The feed is not public.
    case tagged
    /// The GitHub release is public. The feed is not.
    case released
    /// The feed is on `main`. The release is complete.
    case published

    /// The facts that the recovery commands name. Paths are absolute.
    struct Facts: Equatable, Sendable {
        var tag: String
        var title: String
        var sourceCommit: String
        var repositoryRoot: String
        var diskImage: String
        var symbols: String
        var notes: String
    }

    /// What is public after a failure in this phase, and the exact commands that finish or undo it.
    func recovery(_ facts: Facts) -> [String] {
        let text = ReleaseRecoveryText(facts: facts)
        switch self {
        case .local:
            return ["Nothing was published, and no tracked file changed. Correct the cause and run the command again."]
        case .committing: return text.committing
        case .committed: return text.committed
        case .tagged: return text.tagged
        case .released: return text.released
        case .published: return []
        }
    }
}

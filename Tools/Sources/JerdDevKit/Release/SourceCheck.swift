import JerdFoundation

/// The source commit of a release: a clean worktree (also without untracked files) at a known commit.
/// The release checks it before the build and again before the release commit.
struct SourceCheck: Sendable {
    let shell: ReleaseShell

    /// The commit of a clean worktree.
    func requireClean() async throws -> String {
        let status = try await shell.git(["status", "--porcelain", "--untracked-files=all"])
        guard status.isEmpty else {
            throw DevFailure.checkFailed("A release needs a clean worktree, also without untracked files.")
        }
        let commit = try await shell.git(["rev-parse", "HEAD"])
        guard HexEncoding.isHex(commit, length: 40) else {
            throw DevFailure.checkFailed("git did not report the source commit.")
        }
        return commit
    }

    /// The worktree is still clean and still at `commit`.
    func requireClean(at commit: String) async throws {
        guard try await requireClean() == commit else {
            throw DevFailure.checkFailed(
                "The source commit or the tree changed during the release, so the app does not match it. "
                    + "Nothing was published. Run the release again.")
        }
    }
}

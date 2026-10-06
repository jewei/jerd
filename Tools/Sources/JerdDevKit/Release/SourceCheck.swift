import JerdFoundation

/// The source commit of a release: a clean worktree (also without untracked files) at a known commit.
/// Preparation checks it before the build, after the runtime tests, and before it writes the manifest.
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
            throw DevFailure.checkFailed("The source commit changed during the release. Prepare a new candidate.")
        }
    }
}

import Foundation

/// The checks before any build: a clean tree, valid versions, plain-text notes, and, for a
/// publication, `main` at `origin/main` with a successful CI check and no tag or release of the
/// version. With `--prepare-only` the branch and GitHub checks are left out, and nothing goes to GitHub.
struct ReleasePreconditions: Sendable {
    let environment: ReleaseEnvironment
    let inputs: ReleaseInputs

    var shell: ReleaseShell { environment.shell }

    func check() async throws -> ReleaseSource {
        let commit = try await SourceCheck(shell: shell).requireClean()
        if !inputs.prepareOnly {
            try await checkMain(commit)
        }
        let source = try await readSource(commit)
        if !inputs.prepareOnly {
            try await checkUnpublished()
            try await checkContinuousIntegration(commit)
        }
        return source
    }

    /// The branch is `main` of the public repository and equals the fetched `origin/main`.
    func checkMain(_ commit: String) async throws {
        let branch = try await shell.git(["branch", "--show-current"])
        guard branch == ReleaseNames.mainBranch else {
            throw DevFailure.checkFailed(
                "Publish from the main branch, not \(branch.isEmpty ? "a detached HEAD" : branch).")
        }
        let origin = try await shell.git(["remote", "get-url", "origin"])
        guard ReleaseNames.originURLs.contains(origin) else {
            throw DevFailure.checkFailed("The origin remote is not \(ReleaseNames.repository).")
        }
        try await shell.git(["fetch", "--quiet", "--tags", "origin", ReleaseNames.mainBranch])
        let remote = try await shell.git(["rev-parse", "refs/remotes/origin/\(ReleaseNames.mainBranch)"])
        guard remote == commit else {
            throw DevFailure.checkFailed("HEAD is not origin/main. Pull or push first.")
        }
    }

    /// The version file, the committed feed, and the unreleased notes allow this version and build.
    func readSource(_ commit: String) async throws -> ReleaseSource {
        let files = ReleaseSourceFiles(repository: environment.repository, verifier: environment.verifier)
        let versionFile = try files.versionFile()
        let current = try files.version()
        let feed = try files.verifiedFeed()
        try VersionRules.checkFeed(version: inputs.version, build: inputs.build, items: feed.appcast.items)
        // Also with --prepare-only: the candidate folder of a started publication must stay.
        guard try await !hasLocalTag(inputs.tag) else {
            throw DevFailure.checkFailed(
                "The tag \(inputs.tag) exists on this Mac. Released versions are never replaced.")
        }
        let currentTag = ReleaseVersion(current.version).map(ReleaseNames.tag) ?? current.version
        try VersionRules.checkProject(
            version: inputs.version, build: inputs.build, current: current,
            currentIsTagged: try await hasLocalTag(currentTag))
        let changelog = try files.changelog()
        let notes = try ReleaseNotes.forRelease(changelog, version: inputs.version.text)
        return ReleaseSource(
            commit: commit, notes: notes, feed: feed.data, changelog: changelog, versionFile: versionFile)
    }

    /// No tag of the version exists on GitHub, and no release or draft has its name.
    func checkUnpublished() async throws {
        let tag = inputs.tag
        let remote = try await shell.result(
            shell.context.toolchain.git, ["ls-remote", "--exit-code", "--tags", "origin", "refs/tags/\(tag)"],
            limit: TimeLimit.git)
        // Exit status 2 means that no such tag exists. Any other failure is not an answer.
        switch (remote.status, remote.exceededTimeLimit) {
        case (2, nil): break
        case (0, nil):
            throw DevFailure.checkFailed("The tag \(tag) exists on GitHub. Released versions are never replaced.")
        default:
            throw DevFailure.checkFailed(
                "Could not ask GitHub for the tag \(tag): git ls-remote \(remote.failureSummary).")
        }
        let releases = try await shell.gh([
            "api", "repos/\(ReleaseNames.repository)/releases", "--paginate", "--jq", GitHubLookup.releaseFilter,
        ])
        if let release = try GitHubLookup.release(tag, in: releases) {
            let kind = release.draft ? "A draft release" : "A release"
            throw DevFailure.checkFailed("\(kind) named \(tag) exists on GitHub. Inspect it first.")
        }
    }

    /// CI ran `./dev check` for this exact commit with success.
    func checkContinuousIntegration(_ commit: String) async throws {
        let runs = try await shell.gh([
            "api", "repos/\(ReleaseNames.repository)/commits/\(commit)/check-runs?per_page=100", "--paginate",
            "--jq", GitHubLookup.checkRunFilter,
        ])
        if let problem = try GitHubLookup.checkProblem(named: ReleaseNames.checkName, in: runs) {
            throw DevFailure.checkFailed(
                "The commit \(commit.prefix(12)) \(problem). Wait for CI, or run the workflow again for main.")
        }
    }

    func hasLocalTag(_ tag: String) async throws -> Bool {
        try await !shell.git(["tag", "--list", tag]).isEmpty
    }
}

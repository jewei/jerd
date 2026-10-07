import Foundation
import JerdFoundation

/// The last checks and the public steps of a release, in their fixed order: the source check again,
/// the release commit and tag on this Mac, the tag on GitHub, the GitHub release with the disk image and
/// symbols, the check of the uploaded assets, and last `main` with the feed. `main` has the feed that
/// installed apps read, so it goes public only after the disk image exists.
struct ReleasePublication: Sendable {
    /// The step titles, also in the recovery texts and in Tools/README.md.
    enum Title {
        static let checkSource = "Check the source again"
        static let commit = "Commit and tag the release"
        static let pushTag = "Push the tag"
        static let createRelease = "Publish the GitHub release"
        static let checkAssets = "Check the uploaded assets"
        static let pushFeed = "Publish the feed"
    }

    let environment: ReleaseEnvironment
    let inputs: ReleaseInputs
    let source: ReleaseSource
    let layout: CandidateLayout

    var shell: ReleaseShell { environment.shell }

    var steps: [ReleaseStep] {
        [
            ReleaseStep(Title.checkSource) { try await checkSource() },
            ReleaseStep(Title.commit, startPhase: .committing, endPhase: .committed) { try await commit() },
            ReleaseStep(Title.pushTag, endPhase: .tagged) {
                try await shell.git(["push", "--quiet", "origin", "refs/tags/\(inputs.tag)"])
            },
            ReleaseStep(Title.createRelease, endPhase: .released) { try await createRelease() },
            ReleaseStep(Title.checkAssets) { try await checkAssets() },
            ReleaseStep(Title.pushFeed, endPhase: .published) {
                try await shell.git(["push", "--quiet", "origin", "HEAD:\(ReleaseNames.mainBranch)"])
                environment.console.success(
                    "Released Jerd \(inputs.version): https://github.com/\(ReleaseNames.repository)/releases/tag/\(inputs.tag)"
                )
            },
        ]
    }

    /// Nothing is public and no file changed yet. HEAD and the tree are as before the build, and `main`
    /// on GitHub did not move, so the tag goes on a commit that CI checked and `main` can fast-forward.
    func checkSource() async throws {
        try await SourceCheck(shell: shell).requireClean(at: source.commit)
        try await shell.git(["fetch", "--quiet", "origin", ReleaseNames.mainBranch])
        let remote = try await shell.git(["rev-parse", "refs/remotes/origin/\(ReleaseNames.mainBranch)"])
        guard remote == source.commit else {
            throw DevFailure.checkFailed(
                "main moved on GitHub during the build. Nothing was published. Pull main, wait for CI, "
                    + "and run the release again.")
        }
    }

    /// Writes the version, the promoted changelog, and the signed feed, commits exactly these files,
    /// and makes an annotated tag.
    func commit() async throws {
        let files = try ReleaseCommitFiles(
            source: source, feed: try Data(contentsOf: layout.feed), version: inputs.version, build: inputs.build,
            date: environment.clock.now())
        let repository = environment.repository
        try AtomicFile.write(Data(files.versionFile.utf8), to: repository.versionFile, durability: .standard)
        try AtomicFile.write(Data(files.changelog.utf8), to: repository.changelog, durability: .standard)
        try AtomicFile.write(files.feed, to: repository.appcast, durability: .standard)
        try await shell.git(["add", "--"] + ReleaseCommitFiles.paths)
        try await shell.git(["commit", "--quiet", "-m", ReleaseNames.commitMessage(inputs.version)])
        try await shell.git(["tag", "-a", inputs.tag, "-m", ReleaseNames.releaseTitle(inputs.version)])
    }

    /// Creates the public release for the pushed tag with the disk image and the symbols.
    func createRelease() async throws {
        try await shell.gh(
            [
                "release", "create", inputs.tag, layout.file(inputs.diskImageName).path,
                layout.file(inputs.symbolsName).path, "--repo", ReleaseNames.repository, "--verify-tag",
                "--title", ReleaseNames.releaseTitle(inputs.version), "--notes-file", layout.notes.path,
            ], limit: TimeLimit.transfer)
    }

    /// GitHub has both assets with the size and the SHA-256 of the candidate files, so the feed never
    /// names a disk image that differs from the one that Sparkle signed.
    func checkAssets() async throws {
        let output = try await shell.gh([
            "api", "repos/\(ReleaseNames.repository)/releases/tags/\(inputs.tag)", "--jq", GitHubLookup.assetFilter,
        ])
        var expected: [String: GitHubLookup.Asset] = [:]
        for name in [inputs.diskImageName, inputs.symbolsName] {
            let file = layout.file(name)
            let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber
            expected[name] = GitHubLookup.Asset(
                name: name, size: size?.int64Value ?? -1, digest: "sha256:" + (try FileDigest.hexSHA256(of: file)))
        }
        if let problem = try GitHubLookup.assetProblem(expected: expected, in: output) {
            throw DevFailure.checkFailed("The GitHub release \(inputs.tag) \(problem).")
        }
    }

    /// The facts of the recovery commands, with absolute paths.
    static func facts(
        inputs: ReleaseInputs, commit: String, layout: CandidateLayout, repository: Repository
    )
        -> ReleasePhase.Facts
    {
        ReleasePhase.Facts(
            tag: inputs.tag, title: ReleaseNames.releaseTitle(inputs.version), sourceCommit: commit,
            repositoryRoot: repository.root.path, diskImage: layout.file(inputs.diskImageName).path,
            symbols: layout.file(inputs.symbolsName).path, notes: layout.notes.path)
    }
}

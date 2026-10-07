import Foundation
import JerdFoundation

/// The public steps of a release, in their fixed order: the release commit and tag on this Mac, the
/// tag on GitHub, the GitHub release with the disk image and symbols, and last `main` with the feed.
/// `main` has the feed that installed apps read, so it goes public only after the disk image exists.
struct ReleasePublication: Sendable {
    let environment: ReleaseEnvironment
    let inputs: ReleaseInputs
    let source: ReleaseSource
    let layout: CandidateLayout

    var shell: ReleaseShell { environment.shell }

    var steps: [ReleaseStep] {
        [
            ReleaseStep("Commit and tag the release", startPhase: .committing, endPhase: .committed) {
                try await commit()
            },
            ReleaseStep("Push the tag", endPhase: .tagged) {
                try await shell.git(["push", "--quiet", "origin", "refs/tags/\(inputs.tag)"])
            },
            ReleaseStep("Publish the GitHub release", endPhase: .released) { try await createRelease() },
            ReleaseStep("Publish the feed", endPhase: .published) {
                try await shell.git(["push", "--quiet", "origin", "HEAD:\(ReleaseNames.mainBranch)"])
                environment.console.success(
                    "Released Jerd \(inputs.version): https://github.com/\(ReleaseNames.repository)/releases/tag/\(inputs.tag)"
                )
            },
        ]
    }

    /// Writes the version, the promoted changelog, and the signed feed, commits exactly these files,
    /// and makes an annotated tag. It stops first when HEAD or the tree changed during the build.
    func commit() async throws {
        try await SourceCheck(shell: shell).requireClean(at: source.commit)
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

    /// The facts of the recovery commands, with paths relative to the repository.
    static func facts(
        inputs: ReleaseInputs, commit: String, layout: CandidateLayout, repository: Repository
    )
        -> ReleasePhase.Facts
    {
        ReleasePhase.Facts(
            tag: inputs.tag, title: ReleaseNames.releaseTitle(inputs.version), sourceCommit: commit,
            diskImage: repository.relativePath(of: layout.file(inputs.diskImageName)),
            symbols: repository.relativePath(of: layout.file(inputs.symbolsName)),
            notes: repository.relativePath(of: layout.notes))
    }
}

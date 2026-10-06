import Foundation
import JerdFoundation

/// The steps up to the public GitHub release.
extension ReleasePublisher {
    /// The candidate is valid, the origin is the public repository, the source commit is on `main`,
    /// the feed on `main` is the one the candidate extends, and no tag or release has this version.
    func checkPublication(_ facts: PublicationFacts) async throws {
        try await ReleaseValidator(shell: shell, layout: layout).run(publicKeyOnly: true)
        let origin = try await shell.git(["remote", "get-url", "origin"])
        guard ReleaseNames.originURLs.contains(origin) else {
            throw DevFailure.checkFailed("The origin remote is not \(facts.repository).")
        }
        let main = try await fetchMain()
        let ancestor = try await shell.result(
            shell.context.toolchain.git, ["merge-base", "--is-ancestor", facts.manifest.sourceCommit, main],
            limit: TimeLimit.git)
        guard ancestor.status == 0, ancestor.exceededTimeLimit == nil else {
            throw DevFailure.checkFailed("The source commit is not on origin/main. Merge it before publication.")
        }
        try await requireSourceFeed(on: main, facts: facts)
        guard try await GitHubLookup.exactTag(facts.tag, in: tagReferences(facts)) == nil else {
            throw DevFailure.checkFailed("The tag \(facts.tag) exists already. Released assets are never replaced.")
        }
        guard try await GitHubLookup.release(facts.tag, in: releases(facts)) == nil else {
            throw DevFailure.checkFailed("A release or draft named \(facts.tag) exists already. Inspect it on GitHub.")
        }
    }

    /// Creates the draft. A draft of this exact commit from an interrupted run is used again.
    func createDraft(_ facts: PublicationFacts) async throws {
        if let existing = try await GitHubLookup.release(facts.tag, in: releases(facts)) {
            guard existing.draft, existing.target == facts.manifest.sourceCommit else {
                throw DevFailure.checkFailed("A different release named \(facts.tag) exists. Inspect it on GitHub.")
            }
            return
        }
        try await shell.gh(
            [
                "release", "create", facts.tag, layout.file(facts.manifest.dmg).path,
                layout.file(facts.manifest.symbols).path, "--repo", facts.repository,
                "--target", facts.manifest.sourceCommit, "--title", facts.title, "--notes-file", layout.notes.path,
                "--draft",
            ], limit: TimeLimit.transfer)
    }

    /// Downloads the uploaded assets and compares them with the candidate digests.
    func verifyAssets(_ facts: PublicationFacts) async throws {
        let folder = layout.publishedAssets
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await shell.gh(
            ["release", "download", facts.tag, "--repo", facts.repository, "--dir", folder.path],
            limit: TimeLimit.transfer)
        for name in [facts.manifest.dmg, facts.manifest.symbols] {
            let digest = try? FileDigest.hexSHA256(of: folder.appending(path: name))
            guard digest == facts.manifest.files[name] else {
                throw DevFailure.checkFailed("The uploaded asset \(name) differs from the candidate.")
            }
        }
    }

    /// Publishes the release. GitHub then creates the tag, which must name the source commit exactly.
    func makePublic(_ facts: PublicationFacts) async throws {
        try await shell.gh(["release", "edit", facts.tag, "--repo", facts.repository, "--draft=false"])
        let tag = try GitHubLookup.exactTag(facts.tag, in: try await tagReferences(facts))
        guard let tag, tag.type == "commit", tag.sha == facts.manifest.sourceCommit else {
            throw DevFailure.checkFailed(
                "The tag \(facts.tag) does not name the source commit \(facts.manifest.sourceCommit). Inspect it now.")
        }
    }

    func tagReferences(_ facts: PublicationFacts) async throws -> String {
        try await shell.gh([
            "api", "repos/\(facts.repository)/git/matching-refs/tags/\(facts.tag)", "--jq",
            GitHubLookup.referenceFilter,
        ])
    }

    func releases(_ facts: PublicationFacts) async throws -> String {
        try await shell.gh([
            "api", "repos/\(facts.repository)/releases", "--paginate", "--jq", GitHubLookup.releaseFilter,
        ])
    }

    /// Fetches `main` and returns its commit.
    func fetchMain() async throws -> String {
        try await shell.git(["fetch", "origin", "main"])
        return try await shell.git(["rev-parse", "FETCH_HEAD"])
    }

    /// The feed on `main` is still the feed that the candidate extends; otherwise another release
    /// came first and this candidate must be prepared again.
    func requireSourceFeed(on main: String, facts: PublicationFacts) async throws {
        let feed = try await shell.run(
            shell.context.toolchain.git, ["show", "\(main):appcast.xml"], limit: TimeLimit.git)
        guard FileDigest.hexSHA256(of: Data(feed.standardOutput.utf8)) == facts.manifest.sourceFeedSHA256 else {
            throw DevFailure.checkFailed("appcast.xml on main changed after preparation. Prepare a new candidate.")
        }
    }
}

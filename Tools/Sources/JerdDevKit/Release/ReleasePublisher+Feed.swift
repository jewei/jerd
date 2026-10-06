import Foundation

/// The feed steps: a pull request with the signed feed, its merge, and the public feed URL.
extension ReleasePublisher {
    /// Commits the candidate feed on top of `main` and opens a pull request. The commit is made with Git
    /// plumbing and a temporary index, so no worktree exists that could leak. A
    /// pull request of an interrupted run is used again.
    func proposeFeed(_ facts: PublicationFacts) async throws -> Int {
        let listed = try await shell.gh([
            "pr", "list", "--repo", facts.repository, "--head", facts.branch, "--state", "all", "--json",
            "number,state",
        ])
        if let existing = try GitHubLookup.pullRequests(listed).first(where: { $0.state != "CLOSED" }) {
            return existing.number
        }
        let main = try await fetchMain()
        try await requireSourceFeed(on: main, facts: facts)
        let commit = try await feedCommit(on: main, facts: facts)
        try await shell.git(["push", "origin", "\(commit):refs/heads/\(facts.branch)"])
        let body =
            "Publishes the signed update feed of the public release \(facts.tag). "
            + "Merge it to offer the update to installed apps."
        let created = try await shell.gh([
            "pr", "create", "--repo", facts.repository, "--base", "main", "--head", facts.branch,
            "--title", facts.feedCommitMessage, "--body", body,
        ])
        return try GitHubLookup.pullRequestNumber(fromCreateOutput: created)
    }

    /// A commit whose only change from `main` is `appcast.xml`.
    func feedCommit(on main: String, facts: PublicationFacts) async throws -> String {
        let index = layout.feedIndex
        defer { try? FileManager.default.removeItem(at: index) }
        var environment = shell.context.environment
        environment["GIT_INDEX_FILE"] = index.path
        let blob = try await shell.git(["hash-object", "-w", layout.feed.path])
        try await shell.git(["read-tree", main], environment: environment)
        try await shell.git(
            ["update-index", "--add", "--cacheinfo", "100644,\(blob),appcast.xml"], environment: environment)
        let tree = try await shell.git(["write-tree"], environment: environment)
        return try await shell.git(["commit-tree", tree, "-p", main, "-m", facts.feedCommitMessage])
    }

    /// True when the pull request is merged. A closed pull request needs a decision by a person.
    func isMerged(_ number: Int, facts: PublicationFacts) async throws -> Bool {
        let view = try await shell.gh([
            "pr", "view", String(number), "--repo", facts.repository, "--json", "number,state",
        ])
        switch try GitHubLookup.pullRequest(view).state {
        case "MERGED":
            return true
        case "CLOSED":
            throw DevFailure.checkFailed(
                "The feed pull request #\(number) was closed without a merge. Reopen and merge it, then resume.")
        default:
            environment.console.detail(
                "Merge pull request #\(number), then run ./dev release resume \(layout.root.path).")
            return false
        }
    }

    /// True when the URL that installed apps read serves exactly the signed candidate feed.
    func feedIsPublic() async throws -> Bool {
        let expected = try Data(contentsOf: layout.feed)
        let manifest = try ReleaseManifest.decode(try Data(contentsOf: layout.manifest))
        let check = CandidateFeedCheck(
            verifier: environment.verifier,
            version: try manifest.releaseVersion, build: try manifest.buildNumber, minimumMacOS: try manifest.minimum)
        for attempt in 1...max(feedAttempts, 1) {
            if let served = try? await environment.feedFetcher.feed(at: ReleaseNames.feedURL), served == expected {
                try check.verify(feed: served, diskImage: layout.file(manifest.dmg))
                return true
            }
            if attempt < feedAttempts {
                try await environment.clock.sleep(for: feedInterval)
            }
        }
        environment.console.warning(
            "\(ReleaseNames.feedURL.absoluteString) does not serve the new feed yet. Run ./dev release resume later.")
        return false
    }

    /// Removes the merged feed branch. GitHub may have removed it already, so a failure only warns.
    func deleteFeedBranch(_ facts: PublicationFacts) async {
        let result = try? await shell.result(
            shell.context.toolchain.git, ["push", "origin", "--delete", facts.branch], limit: TimeLimit.git)
        if result?.succeeded != true {
            environment.console.detail("The branch \(facts.branch) is already gone or could not be removed.")
        }
    }
}

import Foundation
import JerdFoundation
import os

@testable import JerdDevKit

/// A prepared candidate signed with the test key, and a fake GitHub and Git that keep their state, so
/// a publication can run, stop, and resume without a network.
final class PublicationFixture: Sendable {
    /// What exists on the fake GitHub.
    struct Remote: Sendable {
        var draft = false
        var isPublic = false
        var pullRequest: (number: Int, state: String)?
        var tagCommit: String?
    }

    static let main = String(repeating: "b", count: 40)
    static let feedCommit = String(repeating: "c", count: 40)

    let workspace: ReleaseWorkspace
    let layout: CandidateLayout
    let candidateFeed: Data
    let remote = OSAllocatedUnfairLock(initialState: Remote())

    init(stage: ReleaseStage = .prepared) throws {
        workspace = try ReleaseWorkspace()
        layout = CandidateLayout(root: workspace.path(".build/releases/Jerd-0.2.0-3-test"))
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        candidateFeed = try Self.writeCandidate(
            layout, key: workspace.key, feed: Data(contentsOf: workspace.path("appcast.xml")))
        var state = ReleaseState(startedAt: workspace.clock.now())
        for next in ReleaseStage.allCases where next != .preparing && next != .prepareFailed {
            guard state.stage != stage else { break }
            try state.advance(to: next, at: workspace.clock.now())
        }
        if [.feedProposed, .feedMerged, .published].contains(stage) { state.feedPullRequest = 7 }
        try CandidateStore.save(state, to: layout)
        answerGit()
        answerGitHub()
    }

    /// The disk image, symbols, notes, the signed feed, and `release.json`.
    static func writeCandidate(_ layout: CandidateLayout, key: TestFeedKey, feed source: Data) throws -> Data {
        let image = Data("disk image".utf8)
        try image.write(to: layout.file("Jerd-0.2.0.dmg"))
        try Data("symbols".utf8).write(to: layout.file("Jerd-0.2.0-3.dSYMs.zip"))
        try Data("- New thing.\n".utf8).write(to: layout.notes)
        try source.write(to: layout.sourceFeed)
        let item = AppcastWriter.Item(
            version: ReleaseVersion.release("0.2.0")!, build: 3, minimumMacOS: ReleaseVersion("14.0")!,
            notes: "- New thing.\n", publishedAt: Date(timeIntervalSince1970: 0), archiveLength: Int64(image.count),
            archiveSignature: try key.signature(of: image))
        let unsigned = try AppcastWriter.feed(from: source, adding: item)
        let feed = try key.signedFeed(unsigned)
        try feed.write(to: layout.feed)
        var files: [String: String] = [:]
        for name in ["Jerd-0.2.0.dmg", "Jerd-0.2.0-3.dSYMs.zip", "appcast.xml", "release-notes.md"] {
            files[name] = try FileDigest.hexSHA256(of: layout.file(name))
        }
        let manifest = ReleaseManifest(
            version: "0.2.0", build: "3", teamID: ReleaseFixtures.team, minimumMacOS: "14.0",
            sourceCommit: ReleaseFixtures.commit, sourceFeedSHA256: FileDigest.hexSHA256(of: source),
            dmg: "Jerd-0.2.0.dmg", symbols: "Jerd-0.2.0-3.dSYMs.zip", files: files,
            notarization: .init(app: "a", dmg: "d"), testedSystem: "26.0")
        try manifest.encoded().write(to: layout.manifest)
        return feed
    }

    func publisher(feed: [Data?]? = nil) throws -> ReleasePublisher {
        var publisher = ReleasePublisher(
            environment: try workspace.environment(feed: feed ?? [candidateFeed]), layout: layout)
        publisher.validateCandidate = { _, _ in }
        publisher.feedAttempts = 3
        return publisher
    }

    var runner: FakeReleaseRunner { workspace.runner }

    var stage: ReleaseStage { (try? CandidateStore.load(layout).stage) ?? .preparing }

    private func answerGit() {
        let source = try? String(contentsOf: layout.sourceFeed, encoding: .utf8)
        runner.on("git", ["remote", "get-url", "origin"], output: "git@github.com:jewei/jerd.git\n")
        runner.on("git", ["rev-parse", "FETCH_HEAD"], output: Self.main + "\n")
        runner.on("git", ["show", "\(Self.main):appcast.xml"], output: source ?? "")
        runner.on("git", ["hash-object"], output: String(repeating: "d", count: 40) + "\n")
        runner.on("git", ["write-tree"], output: String(repeating: "e", count: 40) + "\n")
        runner.on("git", ["commit-tree"], output: Self.feedCommit + "\n")
    }

    private func answerGitHub() {
        let remote = self.remote
        let layout = self.layout
        runner.on("gh", ["api", "repos/jewei/jerd/releases"]) { _ in
            let state = remote.withLock { $0 }
            guard state.draft || state.isPublic else { return .init() }
            return .init(
                standardOutput: #"{"tag":"v0.2.0","draft":\#(!state.isPublic),"target":"\#(ReleaseFixtures.commit)"}"#)
        }
        runner.on("gh", ["api", "repos/jewei/jerd/git/matching-refs/tags/v0.2.0"]) { _ in
            guard let sha = remote.withLock({ $0.tagCommit }) else { return .init() }
            return .init(standardOutput: #"{"ref":"refs/tags/v0.2.0","sha":"\#(sha)","type":"commit"}"#)
        }
        runner.on("gh", ["release", "create"], effect: { _ in remote.withLock { $0.draft = true } })
        runner.on(
            "gh", ["release", "download"],
            effect: { invocation in
                let folder = URL(filePath: invocation.arguments.last!)
                for name in ["Jerd-0.2.0.dmg", "Jerd-0.2.0-3.dSYMs.zip"] {
                    try FileManager.default.copyItem(at: layout.file(name), to: folder.appending(path: name))
                }
            })
        runner.on(
            "gh", ["release", "edit"],
            effect: { _ in
                remote.withLock {
                    $0.isPublic = true
                    $0.draft = false
                    $0.tagCommit = ReleaseFixtures.commit
                }
            })
        runner.on("gh", ["pr", "list"]) { _ in
            guard let pull = remote.withLock({ $0.pullRequest }) else { return .init(standardOutput: "[]") }
            return .init(standardOutput: #"[{"number":\#(pull.number),"state":"\#(pull.state)"}]"#)
        }
        runner.on(
            "gh", ["pr", "create"], output: "https://github.com/jewei/jerd/pull/7\n",
            effect: { _ in
                remote.withLock { $0.pullRequest = (7, "OPEN") }
            })
        runner.on("gh", ["pr", "view"]) { _ in
            let state = remote.withLock { $0.pullRequest?.state } ?? "OPEN"
            return .init(standardOutput: #"{"number":7,"state":"\#(state)"}"#)
        }
    }

    /// Sets the fake GitHub to what exists after `stage`.
    func remoteAfter(_ stage: ReleaseStage) {
        let order = ReleaseStage.allCases
        let index = order.firstIndex(of: stage)!
        let created = index >= order.firstIndex(of: .draftCreated)!
        let isPublic = index >= order.firstIndex(of: .releasePublic)!
        let proposed = index >= order.firstIndex(of: .feedProposed)!
        let merged = index >= order.firstIndex(of: .feedMerged)!
        remote.withLock { remote in
            remote.draft = created && !isPublic
            remote.isPublic = isPublic
            remote.tagCommit = isPublic ? ReleaseFixtures.commit : nil
            remote.pullRequest = proposed ? (7, merged ? "MERGED" : "OPEN") : nil
        }
    }

    func merge() { remote.withLock { $0.pullRequest = (7, "MERGED") } }
}

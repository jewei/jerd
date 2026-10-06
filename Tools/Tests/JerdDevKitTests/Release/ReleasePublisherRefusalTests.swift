import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release publication refusals")
struct ReleasePublisherRefusalTests {
    /// Runs `publish` and expects a failure that leaves the candidate at `stage`.
    static func expectRefusal(_ fixture: PublicationFixture, stays stage: ReleaseStage = .prepared) async throws {
        await #expect(throws: DevFailure.self) { _ = try await fixture.publisher().run(resuming: false) }
        #expect(fixture.stage == stage)
    }

    @Test("Refuses an existing tag with exactly the release name")
    func refusesExactTag() async throws {
        let fixture = try PublicationFixture()
        fixture.remote.withLock { $0.tagCommit = ReleaseFixtures.commit }
        try await Self.expectRefusal(fixture)
        #expect(fixture.runner.calls("gh", ["release", "create"]).isEmpty)
    }

    @Test("A tag that only starts with the release name does not block it")
    func ignoresPrefixTags() async throws {
        let fixture = try PublicationFixture()
        let line = #"{"ref":"refs/tags/v0.2.0-rc1","sha":"\#(ReleaseFixtures.commit)","type":"commit"}"#
        fixture.runner.on("gh", ["api", "repos/jewei/jerd/git/matching-refs/tags/v0.2.0"]) { _ in
            let tag = fixture.remote.withLock { $0.tagCommit }
            return .init(
                standardOutput: line
                    + (tag.map { "\n" + #"{"ref":"refs/tags/v0.2.0","sha":"\#($0)","type":"commit"}"# } ?? ""))
        }
        #expect(try await fixture.publisher().run(resuming: false) == .waitingForMerge(7))
    }

    @Test("Refuses an existing draft of the same name")
    func refusesExistingDraft() async throws {
        let fixture = try PublicationFixture()
        fixture.remote.withLock { $0.draft = true }
        try await Self.expectRefusal(fixture)
    }

    @Test("Refuses a source commit that is not on main and another origin")
    func refusesSource() async throws {
        let fixture = try PublicationFixture()
        fixture.runner.on("git", ["merge-base"], status: 1)
        try await Self.expectRefusal(fixture)
        let other = try PublicationFixture()
        other.runner.on("git", ["remote", "get-url", "origin"], output: "git@github.com:someone/jerd.git\n")
        try await Self.expectRefusal(other)
    }

    @Test("Refuses when the feed on main changed after preparation")
    func refusesChangedMainFeed() async throws {
        let fixture = try PublicationFixture()
        fixture.runner.on("git", ["show"], output: "<rss/>")
        try await Self.expectRefusal(fixture)
    }

    @Test("A different uploaded asset stops before the release becomes public")
    func refusesChangedAssets() async throws {
        let fixture = try PublicationFixture()
        fixture.runner.on(
            "gh", ["release", "download"],
            effect: { invocation in
                let folder = URL(filePath: invocation.arguments.last!)
                for name in ["Jerd-0.2.0.dmg", "Jerd-0.2.0-3.dSYMs.zip"] {
                    try Data("other".utf8).write(to: folder.appending(path: name))
                }
            })
        try await Self.expectRefusal(fixture, stays: .draftCreated)
        #expect(fixture.runner.calls("gh", ["release", "edit"]).isEmpty)
    }

    @Test("A public tag on another commit stops before the feed")
    func refusesWrongTag() async throws {
        let fixture = try PublicationFixture()
        fixture.runner.on(
            "gh", ["release", "edit"],
            effect: { _ in
                fixture.remote.withLock {
                    $0.isPublic = true
                    $0.tagCommit = String(repeating: "f", count: 40)
                }
            })
        try await Self.expectRefusal(fixture, stays: .assetsVerified)
        #expect(fixture.runner.calls("gh", ["pr", "create"]).isEmpty)
    }

    @Test("A closed feed pull request needs a person")
    func refusesClosedPullRequest() async throws {
        let fixture = try PublicationFixture(stage: .feedProposed)
        fixture.remoteAfter(.feedProposed)
        fixture.remote.withLock { $0.pullRequest = (7, "CLOSED") }
        await #expect(throws: DevFailure.self) { _ = try await fixture.publisher().run(resuming: true) }
        #expect(fixture.stage == .feedProposed)
    }

    @Test("Publish refuses a started publication, and resume refuses an unstarted or unprepared one")
    func startRules() throws {
        #expect(throws: DevFailure.self) { try ReleasePublisher.requireStart(.draftCreated, resuming: false) }
        #expect(throws: DevFailure.self) { try ReleasePublisher.requireStart(.prepared, resuming: true) }
        #expect(throws: DevFailure.self) { try ReleasePublisher.requireStart(.prepareFailed, resuming: true) }
        #expect(throws: DevFailure.self) { try ReleasePublisher.requireStart(.preparing, resuming: false) }
        try ReleasePublisher.requireStart(.prepared, resuming: false)
        try ReleasePublisher.requireStart(.feedMerged, resuming: true)
    }

    @Test("A changed candidate file stops publication before any command")
    func refusesChangedCandidate() async throws {
        let fixture = try PublicationFixture()
        try Data("changed".utf8).write(to: fixture.layout.notes)
        try await Self.expectRefusal(fixture)
        #expect(fixture.runner.recorded.isEmpty)
    }
}

import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release publication")
struct ReleasePublisherTests {
    @Test("Publish stops at the feed pull request, and resume after the merge finishes")
    func publishThenResume() async throws {
        let fixture = try PublicationFixture()
        defer { fixture.remove() }
        let first = try await fixture.publisher().run(resuming: false)
        #expect(first == .waitingForMerge(7))
        #expect(fixture.stage == .feedProposed)
        fixture.merge()
        let second = try await fixture.publisher().run(resuming: true)
        #expect(second == .published)
        let state = try CandidateStore.load(fixture.layout)
        #expect(
            state.history.map(\.stage) == [
                .preparing, .prepared, .checked, .draftCreated, .assetsVerified, .releasePublic, .feedProposed,
                .feedMerged, .published,
            ])
        #expect(state.feedPullRequest == 7)
    }

    @Test("The draft names the source commit, and the feed goes to a branch, never to main")
    func draftAndFeedBranch() async throws {
        let fixture = try PublicationFixture()
        defer { fixture.remove() }
        _ = try await fixture.publisher().run(resuming: false)
        let create = try #require(fixture.runner.calls("gh", ["release", "create"]).first)
        #expect(create.contains("--draft"))
        #expect(create[create.firstIndex(of: "--target")! + 1] == ReleaseFixtures.commit)
        let pushes = fixture.runner.calls("git", ["push"])
        #expect(pushes.first == ["push", "origin", "\(PublicationFixture.feedCommit):refs/heads/release-feed/v0.2.0"])
        #expect(!pushes.contains { $0.contains { $0.hasSuffix("refs/heads/main") } })
        #expect(fixture.runner.calls("git", ["worktree"]).isEmpty)
    }

    @Test("The feed commit uses a temporary index on top of main and removes it")
    func feedCommitPlumbing() async throws {
        let fixture = try PublicationFixture()
        defer { fixture.remove() }
        _ = try await fixture.publisher().run(resuming: false)
        let indexed = fixture.runner.recorded.filter { $0.environment?["GIT_INDEX_FILE"] != nil }
        #expect(indexed.map { $0.arguments.first! } == ["read-tree", "update-index", "write-tree"])
        #expect(indexed[0].arguments == ["read-tree", PublicationFixture.main])
        #expect(indexed[1].arguments.last == "100644,\(String(repeating: "d", count: 40)),appcast.xml")
        let commit = try #require(fixture.runner.calls("git", ["commit-tree"]).first)
        #expect(commit.contains("-p") && commit.contains(PublicationFixture.main))
        #expect(!FileManager.default.fileExists(atPath: fixture.layout.feedIndex.path))
    }

    @Test("Publication ends only when the public feed URL serves the signed feed")
    func waitsForThePublicFeed() async throws {
        let fixture = try PublicationFixture(stage: .feedMerged)
        defer { fixture.remove() }
        fixture.remoteAfter(.feedMerged)
        let stale = try Data(contentsOf: fixture.layout.sourceFeed)
        let publisher = try fixture.publisher(feed: [nil, stale, fixture.candidateFeed])
        #expect(try await publisher.run(resuming: true) == .published)
        #expect(fixture.workspace.clock.sleeps == [.seconds(30), .seconds(30)])
        let fetcher = try #require(publisher.environment.feedFetcher as? FakeFeedFetcher)
        #expect(
            fetcher.urls.allSatisfy {
                $0.absoluteString == "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml"
            })
    }

    @Test("A feed that the public URL does not serve yet keeps the merged stage for a later resume")
    func feedNotPublicYet() async throws {
        let fixture = try PublicationFixture(stage: .feedMerged)
        defer { fixture.remove() }
        fixture.remoteAfter(.feedMerged)
        let stale = try Data(contentsOf: fixture.layout.sourceFeed)
        #expect(try await fixture.publisher(feed: [stale]).run(resuming: true) == .feedNotYetPublic)
        #expect(fixture.stage == .feedMerged)
    }

    @Test(
        "Resume continues from every stage and repeats no completed step",
        arguments: [ReleaseStage.checked, .draftCreated, .assetsVerified, .releasePublic, .feedProposed, .feedMerged])
    func resumesFromEveryStage(_ stage: ReleaseStage) async throws {
        let fixture = try PublicationFixture(stage: stage)
        defer { fixture.remove() }
        fixture.remoteAfter(stage)
        fixture.merge()
        #expect(try await fixture.publisher().run(resuming: true) == .published)
        let order = ReleaseStage.allCases
        let after = { (other: ReleaseStage) in order.firstIndex(of: stage)! >= order.firstIndex(of: other)! }
        #expect(fixture.runner.calls("gh", ["release", "create"]).isEmpty == after(.draftCreated))
        #expect(fixture.runner.calls("gh", ["release", "edit"]).isEmpty == after(.releasePublic))
        #expect(fixture.runner.calls("gh", ["pr", "create"]).isEmpty == true)
        #expect(fixture.runner.calls("git", ["remote"]).isEmpty)
        #expect(fixture.stage == .published)
    }

    @Test("A draft that an interrupted run created is used again")
    func adoptsInterruptedDraft() async throws {
        let fixture = try PublicationFixture(stage: .checked)
        defer { fixture.remove() }
        fixture.remoteAfter(.draftCreated)
        fixture.merge()
        #expect(try await fixture.publisher().run(resuming: true) == .published)
        #expect(fixture.runner.calls("gh", ["release", "create"]).isEmpty)
    }

    @Test("A finished publication reports success and changes nothing")
    func publishedIsTerminal() async throws {
        let fixture = try PublicationFixture(stage: .published)
        defer { fixture.remove() }
        #expect(try await fixture.publisher().run(resuming: true) == .published)
        #expect(fixture.runner.recorded.isEmpty)
        await #expect(throws: DevFailure.self) { _ = try await fixture.publisher().run(resuming: false) }
    }
}

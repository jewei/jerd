import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Appcast writer")
struct AppcastWriterTests {
    /// A signed channel without items. The repository feed gains an item at each release, so the exact
    /// expectations use this fixed feed.
    static func committedFeed() throws -> Data {
        Data(FeedFixtures.signedChannel.utf8)
    }

    static let item = AppcastWriter.Item(
        version: ReleaseVersion.release("0.2.0")!, build: 3, minimumMacOS: ReleaseVersion("14.0")!,
        notes: "- First line.\n- Second <line> & more.\n", publishedAt: Date(timeIntervalSince1970: 1_791_288_000),
        archiveLength: 1234, archiveSignature: String(repeating: "A", count: 86) + "==")

    @Test("Writes the golden feed: the item after the channel metadata, plain-text notes, no old signature")
    func writesTheGoldenFeed() throws {
        let feed = try AppcastWriter.feed(from: Self.committedFeed(), adding: Self.item)
        let text = String(decoding: feed, as: UTF8.self)
        let golden = GoldenFeed.withItem
        #expect(text == golden)
        #expect(!text.contains("sparkle-signatures"))
        #expect(!text.contains("sparkle-sign-warning"))
    }

    @Test("The written item parses as an appcast item with the release values")
    func itemParses() throws {
        let feed = try AppcastWriter.feed(from: Self.committedFeed(), adding: Self.item)
        let appcast = try Appcast.parse(feed)
        let item = try #require(appcast.items.first)
        #expect(appcast.title == "Jerd updates")
        #expect(item.bundleVersion == "3" && item.shortVersion == "0.2.0")
        #expect(item.minimumSystemVersion == "14.0" && item.hardwareRequirements == "arm64")
        #expect(
            item.enclosure.url.absoluteString == "https://github.com/jewei/jerd/releases/download/v0.2.0/Jerd-0.2.0.dmg"
        )
        #expect(item.enclosure.length == 1234)
    }

    @Test("A newer item goes before the older items")
    func newestFirst() throws {
        let first = try AppcastWriter.feed(from: Self.committedFeed(), adding: Self.item)
        var next = Self.item
        next.version = ReleaseVersion.release("0.3.0")!
        next.build = 4
        let second = try Appcast.parse(AppcastWriter.feed(from: first, adding: next))
        #expect(second.items.map(\.bundleVersion) == ["4", "3"])
    }

    @Test("Adds a newer item before the items of the repository feed")
    func addsToTheRepositoryFeed() throws {
        let repository = try FeedFixtures.repositoryFeed()
        let builds = try Appcast.parse(repository).items.map(\.bundleVersion)
        var next = Self.item
        next.build = (builds.compactMap { Int($0) }.max() ?? 0) + 1
        let written = try Appcast.parse(AppcastWriter.feed(from: repository, adding: next))
        #expect(written.title == "Jerd updates")
        #expect(written.items.map(\.bundleVersion) == ["\(next.build)"] + builds)
    }

    @Test("Formats the publication date in RFC 2822 GMT")
    func formatsDates() {
        #expect(AppcastWriter.rfc2822(Date(timeIntervalSince1970: 0)) == "Thu, 01 Jan 1970 00:00:00 GMT")
    }

    @Test("Refuses a feed without a channel")
    func refusesBadFeeds() {
        #expect(throws: DevFailure.self) { try AppcastWriter.feed(from: Data("<rss/>".utf8), adding: Self.item) }
        #expect(throws: DevFailure.self) { try AppcastWriter.feed(from: Data("nope".utf8), adding: Self.item) }
    }
}

import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Appcast policy")
struct AppcastPolicyTests {
    /// A fixed signed feed, so that the tests do not change when a release adds an item.
    static let committedFeed = FeedFixtures.signedChannel

    private func findings(_ feed: String) -> [String] {
        AppcastPolicy.findings(feed: Data(feed.utf8)).map(\.message)
    }

    @Test("accepts the signed feed fixture")
    func acceptsCommittedFeed() {
        #expect(findings(Self.committedFeed).isEmpty)
    }

    @Test("accepts the repository feed, which each release signs again")
    func acceptsRepositoryFeed() throws {
        #expect(AppcastPolicy.findings(feed: try FeedFixtures.repositoryFeed()).isEmpty)
    }

    @Test("reports an edit after signing through the signed length")
    func reportsEditAfterSigning() {
        let edited = Self.committedFeed.replacingOccurrences(
            of: "<language>en</language>", with: "<language>de</language>\n")
        #expect(findings(edited) == ["The signed length does not match the feed. Sign the feed again."])
    }

    @Test("reports an edit of the same length through the Ed25519 signature")
    func reportsSameLengthEdit() {
        let edited = Self.committedFeed.replacingOccurrences(of: "Jerd updates", with: "Jerd Updates")
        #expect(
            findings(edited) == [
                "The app update feed signature does not match the Jerd key. Sign the feed again with sign_update."
            ])
    }

    @Test("reports a feed that another key signed")
    func reportsAnotherKey() throws {
        let other = try AppcastVerifier(publicKey: Data(repeating: 7, count: 32))
        let messages = AppcastPolicy.keyFindings(Data(Self.committedFeed.utf8)) { other }.map(\.message)
        #expect(messages.count == 1)
    }

    @Test("reports a feed without a signature block")
    func reportsUnsignedFeed() {
        let unsigned = "<rss version=\"2.0\"><channel><title>T</title></channel></rss>"
        #expect(findings(unsigned) == ["The feed has no Sparkle signature block. Sign it with sign_update."])
    }

    @Test("reports XML that is not well-formed")
    func reportsMalformedXML() {
        let messages = findings("<rss version=\"2.0\"><channel>")
        #expect(messages.count == 1)
        #expect(messages.first?.hasPrefix("The feed is not well-formed XML") == true)
    }

    @Test("reports a wrong root, version, and channel count")
    func reportsWrongStructure() throws {
        let atom = try XMLDocument(xmlString: "<feed/>")
        #expect(AppcastPolicy.structureFindings(atom).map(\.message) == ["The root element must be <rss>."])
        let twoChannels = try XMLDocument(xmlString: "<rss version=\"1.0\"><channel/><channel/></rss>")
        #expect(
            AppcastPolicy.structureFindings(twoChannels).map(\.message) == [
                "The <rss> element must have version=\"2.0\".", "The feed must have exactly one <channel>.",
            ])
    }

    @Test("requires an HTTPS enclosure with an EdDSA signature on every item")
    func checksItems() throws {
        let feed = """
            <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
            <title>T</title>
            <item><enclosure url="https://example.com/Jerd.dmg" sparkle:edSignature="abc" length="1"/></item>
            <item><enclosure url="http://example.com/Jerd.dmg" length="1"/></item>
            <item><title>No archive</title></item>
            </channel></rss>
            """
        let document = try XMLDocument(xmlString: feed)
        #expect(
            AppcastPolicy.structureFindings(document).map(\.message) == [
                "Item 2 must have an HTTPS enclosure URL.", "Item 2 has no sparkle:edSignature.",
                "Item 3 has no <enclosure>.",
            ])
    }

    @Test("requires a 64-byte signature")
    func checksSignatureSize() {
        let feed = "<rss/><!-- sparkle-signatures:\nedSignature: AAAA\nlength: 6\n-->"
        #expect(
            AppcastPolicy.signatureFindings(Data(feed.utf8)).map(\.message) == [
                "The signature block has no valid edSignature."
            ])
    }
}

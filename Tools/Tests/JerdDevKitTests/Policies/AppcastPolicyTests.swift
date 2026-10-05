import Foundation
import Testing

@testable import JerdDevKit

@Suite("Appcast policy")
struct AppcastPolicyTests {
    /// The committed `appcast.xml`, byte for byte.
    static let committedFeed =
        "<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\"?><!-- sparkle-sign-warning:\n"
        + "IMPORTANT: This file was signed by Sparkle. Any modifications to this file requires re-signing this "
        + "file with generate_appcast or sign_update! The signed signature will be embedded at the end of this file.\n"
        + "--><rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\" version=\"2.0\">\n"
        + "  <channel>\n"
        + "    <title>Jerd updates</title>\n"
        + "    <link>https://github.com/jewei/jerd</link>\n"
        + "    <description>Signed updates for Jerd on macOS.</description>\n"
        + "    <language>en</language>\n"
        + "  </channel>\n"
        + "</rss><!-- sparkle-signatures:\n"
        + "edSignature: 74JGYRhmmNYgDEHLsZgwy4xjiLuRksJ9s9hunH76T9IJlSaFsYX8r16i8CyXbSZSBG4M9kTFQPxP9J0x/PFTDw==\n"
        + "length: 582\n"
        + "-->\n"

    private func findings(_ feed: String) -> [String] {
        AppcastPolicy.findings(feed: Data(feed.utf8)).map(\.message)
    }

    @Test("accepts the committed signed feed")
    func acceptsCommittedFeed() {
        #expect(findings(Self.committedFeed).isEmpty)
    }

    @Test("reports an edit after signing through the signed length")
    func reportsEditAfterSigning() {
        let edited = Self.committedFeed.replacingOccurrences(
            of: "<language>en</language>", with: "<language>de</language>\n")
        #expect(findings(edited) == ["The signed length does not match the feed. Sign the feed again."])
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

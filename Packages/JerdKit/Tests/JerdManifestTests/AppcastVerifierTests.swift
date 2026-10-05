import CryptoKit
import Foundation
import JerdFoundation
import JerdManifest
import Testing

@Suite struct AppcastVerifierTests {
    @Test func committedFeedVerifiesWithTheOfficialPublicKeyOnly() throws {
        let appcast = try AppcastVerifier.official().verifiedAppcast(Fixture.data("appcast.xml"))
        #expect(appcast.title == "Jerd updates")
        #expect(appcast.items.isEmpty)
    }

    @Test func changedFeedContentFailsTheSignature() throws {
        var text = String(decoding: try Fixture.data("appcast.xml"), as: UTF8.self)
        text = text.replacingOccurrences(of: "Jerd updates", with: "Jerd update!")
        #expect(throws: JerdError.invalid("The app update feed signature does not match the Jerd key.")) {
            try AppcastVerifier.official().verifiedAppcast(Data(text.utf8))
        }
    }

    @Test func feedSignedWithAnotherKeyFails() throws {
        let signer = FeedSigner()
        let feed = signer.sign(FeedSigner.feed(items: ""))
        #expect(throws: JerdError.invalid("The app update feed signature does not match the Jerd key.")) {
            try AppcastVerifier.official().verifiedAppcast(feed)
        }
        #expect(try signer.verifier().verifiedAppcast(feed).items.isEmpty)
    }

    @Test func signedItemsParseWithTheirSparkleFields() throws {
        let signer = FeedSigner()
        let archive = Data("update archive".utf8)
        let item = FeedSigner.item(signature: signer.signature(of: archive), length: archive.count)
        let appcast = try signer.verifier().verifiedAppcast(signer.sign(FeedSigner.feed(items: item)))
        let parsed = try #require(appcast.items.first)
        #expect(parsed.bundleVersion == "3" && parsed.shortVersion == "0.2.0")
        #expect(parsed.minimumSystemVersion == "14.0" && parsed.hardwareRequirements == "arm64")
        #expect(
            parsed.enclosure.url.absoluteString
                == "https://github.com/jewei/jerd/releases/download/v0.2.0/Jerd-0.2.0.dmg")
        #expect(parsed.enclosure.length == Int64(archive.count))
    }

    @Test func archiveMustHaveTheEnclosureLengthAndSignature() throws {
        let signer = FeedSigner()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-appcast-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Jerd.dmg")
        let archive = Data("update archive".utf8)
        try archive.write(to: file)
        let url = try #require(URL(string: "https://github.com/jewei/jerd/releases/download/v1/Jerd.dmg"))
        let good = AppcastEnclosure(url: url, length: Int64(archive.count), signature: signer.signature(of: archive))
        try signer.verifier().verifyArchive(file, enclosure: good)
        let longer = AppcastEnclosure(url: url, length: good.length + 1, signature: good.signature)
        #expect(throws: JerdError.self) { try signer.verifier().verifyArchive(file, enclosure: longer) }
        try Data("update archivf".utf8).write(to: file)
        #expect(throws: JerdError.invalid("The update archive signature does not match the Jerd key.")) {
            try signer.verifier().verifyArchive(file, enclosure: good)
        }
    }

    @Test func signatureBlockRulesFollowSparkle() throws {
        let content = Data("<rss/>".utf8)
        let signature = Data(repeating: 1, count: 64).base64EncodedString()
        func feed(_ block: String) -> Data { content + Data(block.utf8) }
        #expect(throws: JerdError.invalid("The app update feed has no signature.")) { try SignedFeed(content) }
        #expect(throws: JerdError.invalid("The app update feed signature is malformed.")) {
            try SignedFeed(feed("<!-- sparkle-signatures:\nedSignature: AAAA\nlength: 6\n-->\n"))
        }
        #expect(throws: JerdError.invalid("The app update feed changed after it was signed.")) {
            try SignedFeed(feed("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: 7\n-->\n"))
        }
        let parsed = try SignedFeed(feed("<!-- sparkle-signatures:\nedSignature: \(signature)\nlength: 6\n-->\n"))
        #expect(parsed.content == content && parsed.signature.count == 64)
    }

    @Test(arguments: [
        "<rss version=\"2.0\"><channel><title>T</title><item><sparkle:version>1</sparkle:version></item></channel></rss>",
        "<rss version=\"1.0\"><channel><title>T</title></channel></rss>",
        "<rss version=\"2.0\"></rss>", "not xml",
    ])
    func malformedAppcastsAreRefused(_ body: String) {
        let text = body.replacingOccurrences(
            of: "<rss ", with: "<rss xmlns:sparkle=\"\(Appcast.sparkleNamespace)\" ")
        #expect(throws: JerdError.self) { try Appcast.parse(Data(text.utf8)) }
    }

    @Test func itemWithoutAnHTTPSEnclosureIsRefused() throws {
        let item = FeedSigner.item(signature: Data(count: 64), length: 1)
            .replacingOccurrences(of: "https://github.com", with: "http://github.com")
        #expect(throws: JerdError.invalid("Item 1 of the app update feed must have an HTTPS enclosure URL.")) {
            try Appcast.parse(Data(FeedSigner.feed(items: item).utf8))
        }
    }
}

/// Signs feeds and archives as Sparkle's `sign_update` does, with a new test key.
struct FeedSigner {
    let key = Curve25519.Signing.PrivateKey()

    func verifier() throws -> AppcastVerifier { try AppcastVerifier(publicKey: key.publicKey.rawRepresentation) }

    func signature(of data: Data) -> Data { (try? key.signature(for: data)) ?? Data() }

    func sign(_ text: String) -> Data {
        let content = Data(text.utf8)
        let block =
            "<!-- sparkle-signatures:\nedSignature: \(signature(of: content).base64EncodedString())\n"
            + "length: \(content.count)\n-->\n"
        return content + Data(block.utf8)
    }

    static func feed(items: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><rss xmlns:sparkle=\"\(Appcast.sparkleNamespace)\" version=\"2.0\">"
            + "<channel><title>Jerd updates</title>\(items)</channel></rss>"
    }

    static func item(signature: Data, length: Int) -> String {
        "<item><title>Jerd 0.2.0</title><sparkle:version>3</sparkle:version>"
            + "<sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>"
            + "<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
            + "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"
            + "<enclosure url=\"https://github.com/jewei/jerd/releases/download/v0.2.0/Jerd-0.2.0.dmg\" "
            + "length=\"\(length)\" type=\"application/octet-stream\" "
            + "sparkle:edSignature=\"\(signature.base64EncodedString())\"/></item>"
    }
}

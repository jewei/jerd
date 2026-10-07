import Foundation
import JerdManifest

/// The appcast of one update case: one channel and, when the case offers an update, one item for
/// version 2 with the signed archive.
enum UpdateTestFeed {
    /// The item title. The altered-feed case changes this text after signing.
    static let itemTitle = "Updater Test 2.0"
    static let alteredItemTitle = "Updater Test 9.0"

    /// The archive of an update that the feed offers.
    struct Archive: Equatable, Sendable {
        var url: URL
        var length: Int64
        var signature: String
    }

    /// The feed text before Sparkle's `sign_update` appends the signature block.
    static func text(archive: Archive?) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="utf-8"?>"#,
            #"<rss xmlns:sparkle="\#(Appcast.sparkleNamespace)" version="2.0">"#,
            "<channel>",
            "<title>Jerd isolated updater test</title>",
        ]
        if let archive {
            lines += [
                "<item>",
                "<title>\(itemTitle)</title>",
                "<sparkle:version>2</sparkle:version>",
                "<sparkle:shortVersionString>2.0</sparkle:shortVersionString>",
                "<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>",
                #"<enclosure url="\#(escaped(archive.url.absoluteString))" length="\#(archive.length)" "#
                    + #"type="application/octet-stream" sparkle:edSignature="\#(escaped(archive.signature))"/>"#,
                "</item>",
            ]
        }
        lines += ["</channel>", "</rss>", ""]
        return lines.joined(separator: "\n")
    }

    /// The signed feed with one changed word, which must break its signature.
    static func altered(_ feed: Data) throws -> Data {
        let text = String(decoding: feed, as: UTF8.self)
        guard text.contains(itemTitle) else {
            throw DevFailure.checkFailed("The signed test feed has no item to change.")
        }
        return Data(text.replacingOccurrences(of: itemTitle, with: alteredItemTitle).utf8)
    }

    /// Flips the lowest bit of the byte at `offset`, which must break the archive signature.
    static func flipBit(in file: URL, at offset: UInt64 = 100) throws {
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        guard let byte = try handle.read(upToCount: 1)?.first else {
            throw DevFailure.checkFailed("The test archive is shorter than \(offset + 1) bytes.")
        }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: Data([byte ^ 1]))
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }
}

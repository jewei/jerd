import Foundation
import JerdManifest

/// Adds the item of a new release to the published feed. Pure: bytes in, bytes out.
///
/// The old Sparkle signature comments are removed, because `sign_update` signs the new content. The
/// item goes after the channel metadata and before older items (newest first), so the document reads
/// like a normal RSS feed. The notes are plain text with `sparkle:format`, so
/// Sparkle shows the Markdown list as written instead of one HTML paragraph.
enum AppcastWriter {
    /// The new item.
    struct Item: Equatable, Sendable {
        var version: ReleaseVersion
        var build: Int
        var minimumMacOS: ReleaseVersion
        var notes: String
        var publishedAt: Date
        var archiveLength: Int64
        /// The base64 EdDSA signature of the archive, from `sign_update -p`.
        var archiveSignature: String
    }

    static func feed(from source: Data, adding item: Item) throws -> Data {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: source, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw DevFailure.checkFailed("The source feed is not valid XML.")
        }
        for comment in (document.children ?? []).reversed() where comment.kind == .comment {
            if comment.stringValue?.contains("sparkle-sign") == true {
                comment.detach()
            }
        }
        guard let channel = document.rootElement()?.elements(forName: "channel").first else {
            throw DevFailure.checkFailed("The source feed has no channel.")
        }
        let children = channel.children ?? []
        let index = children.firstIndex { ($0 as? XMLElement)?.name == "item" } ?? children.count
        channel.insertChild(element(for: item), at: index)
        document.characterEncoding = "utf-8"
        return document.xmlData(options: [.nodePrettyPrint, .nodeCompactEmptyElement])
    }

    static func element(for item: Item) -> XMLElement {
        let element = XMLElement(name: "item")
        element.addChild(XMLElement(name: "title", stringValue: ReleaseNames.releaseTitle(item.version)))
        element.addChild(XMLElement(name: "pubDate", stringValue: rfc2822(item.publishedAt)))
        element.addChild(sparkle("version", String(item.build)))
        element.addChild(sparkle("shortVersionString", item.version.text))
        element.addChild(sparkle("minimumSystemVersion", item.minimumMacOS.text))
        element.addChild(sparkle("hardwareRequirements", ReleaseNames.architecture))
        let description = XMLElement(name: "description", stringValue: item.notes)
        description.addAttribute(sparkleAttribute("format", "plain-text"))
        element.addChild(description)
        let enclosure = XMLElement(name: "enclosure")
        for (name, value) in [
            ("url", ReleaseNames.diskImageURL(item.version).absoluteString), ("length", String(item.archiveLength)),
            ("type", "application/octet-stream"),
        ] {
            enclosure.addAttribute(attribute(name, value))
        }
        enclosure.addAttribute(sparkleAttribute("edSignature", item.archiveSignature))
        element.addChild(enclosure)
        return element
    }

    /// RFC 2822 date in GMT, for example `Tue, 06 Oct 2026 12:00:00 GMT`.
    static func rfc2822(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private static func sparkle(_ name: String, _ value: String) -> XMLElement {
        let element = XMLElement(name: "sparkle:\(name)", uri: Appcast.sparkleNamespace)
        element.stringValue = value
        return element
    }

    private static func sparkleAttribute(_ name: String, _ value: String) -> XMLNode {
        let node = XMLNode(kind: .attribute)
        node.name = "sparkle:\(name)"
        node.uri = Appcast.sparkleNamespace
        node.stringValue = value
        return node
    }

    private static func attribute(_ name: String, _ value: String) -> XMLNode {
        let node = XMLNode(kind: .attribute)
        node.name = name
        node.stringValue = value
        return node
    }
}

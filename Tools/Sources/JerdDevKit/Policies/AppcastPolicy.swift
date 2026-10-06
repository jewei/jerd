import Foundation
import JerdFoundation
import JerdManifest

/// `appcast.xml` must be an RSS 2.0 feed with one channel, every item must point to an HTTPS archive
/// with an EdDSA signature, and the feed must end with Sparkle's signature block. Installed apps require
/// a signed feed, so an edit without a new signature breaks every update check.
///
/// When the structure and the signature block are valid, the policy verifies the Ed25519 signature with
/// the official public key (`AppcastVerifier`), so an edit of the same length fails too (review
/// tooling-r1 M2). This needs no private key, so CI checks it.
enum AppcastPolicy {
    static let file = "appcast.xml"
    static let signatureMarker = "<!-- sparkle-signatures:"

    static func findings(feed: Data) -> [PolicyFinding] {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: feed, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            return [finding("The feed is not well-formed XML: \(error.localizedDescription)")]
        }
        let findings = structureFindings(document) + signatureFindings(feed)
        return findings.isEmpty ? keyFindings(feed) : findings
    }

    static func structureFindings(_ document: XMLDocument) -> [PolicyFinding] {
        guard let rss = document.rootElement(), rss.name == "rss" else {
            return [finding("The root element must be <rss>.")]
        }
        var findings: [PolicyFinding] = []
        if rss.attribute(forName: "version")?.stringValue != "2.0" {
            findings.append(finding("The <rss> element must have version=\"2.0\"."))
        }
        let channels = rss.elements(forName: "channel")
        guard channels.count == 1, let channel = channels.first else {
            return findings + [finding("The feed must have exactly one <channel>.")]
        }
        if channel.elements(forName: "title").isEmpty {
            findings.append(finding("The channel has no <title>."))
        }
        for (index, item) in channel.elements(forName: "item").enumerated() {
            findings += itemFindings(item, number: index + 1)
        }
        return findings
    }

    static func itemFindings(_ item: XMLElement, number: Int) -> [PolicyFinding] {
        guard let enclosure = item.elements(forName: "enclosure").first else {
            return [finding("Item \(number) has no <enclosure>.")]
        }
        var findings: [PolicyFinding] = []
        let url = enclosure.attribute(forName: "url")?.stringValue.flatMap { URLComponents(string: $0) }
        if url?.scheme != "https" || (url?.host ?? "").isEmpty {
            findings.append(finding("Item \(number) must have an HTTPS enclosure URL."))
        }
        if enclosure.attribute(forName: "sparkle:edSignature")?.stringValue == nil {
            findings.append(finding("Item \(number) has no sparkle:edSignature."))
        }
        return findings
    }

    /// Sparkle signs the bytes before its signature comment and records their count as `length`.
    static func signatureFindings(_ feed: Data) -> [PolicyFinding] {
        guard let marker = feed.range(of: Data(signatureMarker.utf8)) else {
            return [finding("The feed has no Sparkle signature block. Sign it with sign_update.")]
        }
        let block = String(decoding: feed[marker.lowerBound...], as: UTF8.self)
        let fields = signatureFields(block)
        var findings: [PolicyFinding] = []
        if Data(base64Encoded: fields["edSignature"] ?? "")?.count != 64 {
            findings.append(finding("The signature block has no valid edSignature."))
        }
        if fields["length"] != String(marker.lowerBound - feed.startIndex) {
            findings.append(finding("The signed length does not match the feed. Sign the feed again."))
        }
        return findings
    }

    /// The signature over the signed bytes must verify with the official Jerd key.
    static func keyFindings(
        _ feed: Data, verifier: () throws -> AppcastVerifier = AppcastVerifier.official
    ) -> [PolicyFinding] {
        do {
            _ = try verifier().verifiedAppcast(feed)
            return []
        } catch let error as JerdError {
            return [finding("\(error.message) Sign the feed again with sign_update.")]
        } catch {
            return [finding("The feed signature cannot be checked: \(error.localizedDescription)")]
        }
    }

    static func signatureFields(_ block: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in block.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            fields[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return fields
    }

    private static func finding(_ message: String) -> PolicyFinding {
        PolicyFinding(file: file, message: message)
    }
}

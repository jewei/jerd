import Foundation
import JerdFoundation

/// Reads one `<item>` element. Sparkle values can be child elements or enclosure attributes.
enum AppcastItemParser {
    static func parse(_ item: XMLElement, number: Int) throws -> AppcastItem {
        guard let enclosureElement = item.elements(forName: "enclosure").first else {
            throw invalid(number, "has no enclosure")
        }
        guard let version = value("version", in: item, enclosure: enclosureElement), !version.isEmpty else {
            throw invalid(number, "has no sparkle:version")
        }
        return AppcastItem(
            title: item.elements(forName: "title").first?.stringValue,
            bundleVersion: version,
            shortVersion: value("shortVersionString", in: item, enclosure: enclosureElement),
            minimumSystemVersion: value("minimumSystemVersion", in: item, enclosure: nil),
            hardwareRequirements: value("hardwareRequirements", in: item, enclosure: nil),
            enclosure: try enclosure(enclosureElement, number: number))
    }

    private static func enclosure(_ element: XMLElement, number: Int) throws -> AppcastEnclosure {
        guard let text = element.attribute(forName: "url")?.stringValue, let url = URL(string: text),
            url.scheme == "https", !(url.host ?? "").isEmpty
        else { throw invalid(number, "must have an HTTPS enclosure URL") }
        guard let lengthText = element.attribute(forName: "length")?.stringValue, let length = Int64(lengthText),
            length > 0
        else { throw invalid(number, "must have a positive enclosure length") }
        guard let encoded = sparkleAttribute("edSignature", of: element), let signature = Data(base64Encoded: encoded),
            signature.count == 64
        else { throw invalid(number, "must have a valid sparkle:edSignature") }
        return AppcastEnclosure(url: url, length: length, signature: signature)
    }

    /// A `sparkle:` child element value, else the `sparkle:` attribute of the enclosure.
    private static func value(_ name: String, in item: XMLElement, enclosure: XMLElement?) -> String? {
        let child = item.children?.compactMap { $0 as? XMLElement }.first { isSparkle($0, name) }
        if let text = child?.stringValue { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return enclosure.flatMap { sparkleAttribute(name, of: $0) }
    }

    private static func sparkleAttribute(_ name: String, of element: XMLElement) -> String? {
        element.attributes?.first { isSparkle($0, name) }?.stringValue
    }

    private static func isSparkle(_ node: XMLNode, _ name: String) -> Bool {
        node.localName == name && (node.uri == Appcast.sparkleNamespace || node.name == "sparkle:\(name)")
    }

    private static func invalid(_ number: Int, _ problem: String) -> JerdError {
        .invalid("Item \(number) of the app update feed \(problem).")
    }
}

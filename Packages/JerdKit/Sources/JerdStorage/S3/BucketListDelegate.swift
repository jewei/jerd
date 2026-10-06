import Foundation

/// Collects the text of `ListAllMyBucketsResult/Buckets/Bucket/Name` elements. It lives for one
/// synchronous parse only.
final class BucketListDelegate: NSObject, XMLParserDelegate {
    private static let namePath = ["ListAllMyBucketsResult", "Buckets", "Bucket", "Name"]

    private(set) var names: Set<String> = []
    /// True when the root element is `ListAllMyBucketsResult`.
    private(set) var isBucketList = false
    private var path: [String] = []
    private var text = ""

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if path.isEmpty { isBucketList = elementName == Self.namePath[0] }
        path.append(elementName)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
    ) {
        if path == Self.namePath { names.insert(text) }
        path.removeLast()
        text = ""
    }
}

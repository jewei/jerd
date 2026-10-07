import Foundation
import JerdFoundation

/// A parsed RSS 2.0 appcast with one channel. Parse only content whose signature is verified.
public struct Appcast: Equatable, Sendable {
    /// The Sparkle XML namespace.
    public static let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    public let title: String
    public let items: [AppcastItem]

    public init(title: String, items: [AppcastItem]) {
        self.title = title
        self.items = items
    }

    /// Parses appcast XML. External entities are never loaded.
    /// - Throws: `.invalid` for a malformed feed or item.
    public static func parse(_ data: Data) throws -> Appcast {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        } catch {
            throw JerdError.invalid("The app update feed is not valid XML.")
        }
        guard let rss = document.rootElement(), rss.name == "rss",
            rss.attribute(forName: "version")?.stringValue == "2.0"
        else { throw JerdError.invalid("The app update feed is not an RSS 2.0 document.") }
        let channels = rss.elements(forName: "channel")
        guard channels.count == 1, let channel = channels.first,
            let title = channel.elements(forName: "title").first?.stringValue
        else { throw JerdError.invalid("The app update feed must have one channel with a title.") }
        let items = try channel.elements(forName: "item").enumerated().map { index, element in
            try AppcastItemParser.parse(element, number: index + 1)
        }
        return Appcast(title: title, items: items)
    }
}

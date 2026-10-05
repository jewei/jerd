import Foundation

/// A safe relative POSIX path that cannot leave the folder it is resolved against.
///
/// Rules: not empty, no leading `/`, no `\`, no control character, and no empty, `.`, or `..`
/// component. Archives, receipts, and manifests all use this one type.
public struct RelativePath: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// The components, each non-empty and never `.` or `..`.
    public let components: [String]

    /// Validates a strict relative path, for example `bin/php` (not `./bin/php` or `bin//php`).
    public init?(_ text: String) {
        guard Self.hasSafeCharacters(text) else { return nil }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        components = parts
    }

    /// Validates an archive entry name: empty and `.` components are dropped, `..` is refused.
    /// For example `./root//bin/` becomes `root/bin`.
    public init?(normalizing text: String) {
        guard Self.hasSafeCharacters(text) else { return nil }
        let parts = text.split(separator: "/").map(String.init).filter { $0 != "." }
        guard !parts.isEmpty, !parts.contains("..") else { return nil }
        components = parts
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let path = Self(try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "The relative path is unsafe.")
        }
        self = path
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    /// The path text, components joined with `/`.
    public var string: String { components.joined(separator: "/") }

    public var description: String { string }

    /// The URL of this path inside `folder`.
    public func url(in folder: URL) -> URL {
        components.reduce(folder) { $0.appendingPathComponent($1) }
    }

    /// This path followed by `other`.
    public func appending(_ other: RelativePath) -> RelativePath {
        RelativePath(components: components + other.components)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.string < rhs.string }

    private init(components: [String]) { self.components = components }

    private static func hasSafeCharacters(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("/") && !text.contains("\\")
            && !text.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

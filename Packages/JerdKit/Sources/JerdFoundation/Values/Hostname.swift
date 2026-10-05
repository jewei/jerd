import Foundation

/// A validated, lowercase `.test` hostname. Only `HostnamePolicy` creates one.
public struct Hostname: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// The lowercase hostname text, for example `shop.example.test`.
    public let value: String

    init(checked value: String) { self.value = value }

    /// Validates `text` with `HostnamePolicy.validate(_:)`.
    public init(_ text: String) throws {
        self = try HostnamePolicy.validate(text)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        self = try HostnamePolicy.validate(text)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public var description: String { value }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

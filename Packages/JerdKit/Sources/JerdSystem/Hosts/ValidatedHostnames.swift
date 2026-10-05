import JerdFoundation

/// 1 to 256 unique `.test` hostnames, lowercase and sorted. The host set of one HTTPS setup.
public struct ValidatedHostnames: Hashable, Sendable, Codable {
    /// The hostnames in sorted order.
    public let values: [Hostname]

    /// Validates `texts` with `HostnamePolicy.validateSet`. Uppercase letters become lowercase.
    public init(_ texts: [String]) throws {
        values = try HostnamePolicy.validateSet(texts)
    }

    /// Validates a set of hostnames that are already single valid names.
    public init(_ hostnames: [Hostname]) throws {
        try self.init(hostnames.map(\.value))
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode([String].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(strings)
    }

    /// The hostname texts in sorted order.
    public var strings: [String] { values.map(\.value) }

    /// The hostname texts as a set.
    public var set: Set<String> { Set(strings) }
}

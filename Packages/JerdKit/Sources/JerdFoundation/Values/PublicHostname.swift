/// A lowercase public DNS name that a Cloudflare route can use, for example `preview.example.com`.
///
/// It is the one rule for public hostnames: tunnels save it, and the web environment restores it
/// as the request Host. `localhost` and `.test` names cannot be one: Cloudflare cannot route
/// them, and Caddy must never receive another site's `.test` name as Host. Other private names,
/// such as `.local`, pass this rule.
package struct PublicHostname: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The hostname text, for example `preview.example.com`.
    package let value: String

    /// Nil for a name that breaks `HostnamePolicy.isDNSName(_:)`, for `localhost` or a name below
    /// it, for a `.test` name, and for an IPv4 literal. Callers give their own message.
    package init?(_ text: String) {
        guard HostnamePolicy.isDNSName(text), !Self.isLocal(text), !Self.isAddressLiteral(text) else { return nil }
        value = text
    }

    /// True for an IPv4 literal: a dotted name whose last label is all digits. No top-level domain
    /// is numeric, so such a name cannot be a public hostname.
    package static func isAddressLiteral(_ text: String) -> Bool {
        guard let last = text.split(separator: ".", omittingEmptySubsequences: false).last, !last.isEmpty
        else { return false }
        return last.utf8.allSatisfy { (48...57).contains($0) }
    }

    /// True for `localhost`, a name below it, and a name in the reserved `.test` domain.
    private static func isLocal(_ text: String) -> Bool {
        text == "localhost" || text.hasSuffix(".localhost") || text.hasSuffix(".test")
    }

    package var description: String { value }

    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

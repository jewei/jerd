/// A Cloudflare domain that the API token can edit. Jerd creates a tunnel in the zone's account.
public struct CloudflareZone: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    /// The domain, for example `example.com`.
    public let name: String
    public let accountID: String

    public init(id: String, name: String, accountID: String) {
        self.id = id
        self.name = name
        self.accountID = accountID
    }

    /// The public hostname of `subdomain` in this zone. An empty subdomain is the domain itself.
    public func hostname(subdomain: String) -> String {
        let label = subdomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return label.isEmpty ? name : "\(label).\(name)"
    }
}

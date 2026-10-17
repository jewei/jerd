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

    /// True for the domain itself or one label below it: Cloudflare's free Universal SSL
    /// certificate covers only these names, so a deeper proxied name fails in the browser.
    public func isCertificateCovered(_ hostname: String) -> Bool {
        guard hostname != name else { return true }
        guard hostname.hasSuffix(".\(name)") else { return false }
        let label = hostname.dropLast(name.count + 1)
        return !label.isEmpty && !label.contains(".")
    }
}

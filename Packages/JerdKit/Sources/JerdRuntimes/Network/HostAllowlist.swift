import Foundation
import JerdFoundation

/// The one rule for every runtime URL: HTTPS on port 443, no user or password, and a listed host.
///
/// Every request, every redirect, and every final response URL must pass it.
public struct HostAllowlist: Hashable, Sendable {
    /// The publishers of every runtime that Jerd supplies.
    public static let runtimeSources = HostAllowlist(hosts: [
        "api.github.com", "github.com", "raw.githubusercontent.com", "release-assets.githubusercontent.com",
        "objects.githubusercontent.com", "codeload.github.com", "getcomposer.org", "repo.packagist.org",
        "packagist.org", "download.redis.io", "dev.mysql.com", "cdn.mysql.com", "downloads.mysql.com",
        "repo.mysql.com",
    ])

    /// Lowercase host names.
    public let hosts: Set<String>

    public init(hosts: Set<String>) { self.hosts = Set(hosts.map { $0.lowercased() }) }

    /// True when `url` passes the rule.
    public func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), hosts.contains(host) else { return false }
        return url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    /// - Throws: `.invalid("The update source has an unsupported download URL.")`.
    public func validate(_ url: URL) throws {
        guard allows(url) else { throw Self.unsupported }
    }

    static var unsupported: JerdError { .invalid("The update source has an unsupported download URL.") }
}

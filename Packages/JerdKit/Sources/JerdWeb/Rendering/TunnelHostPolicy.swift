import JerdFoundation

/// Restores only a site's registered public hosts after the local TLS and Host checks.
enum TunnelHostPolicy {
    /// Sets a literal saved hostname instead of reflecting an arbitrary forwarded header into PHP.
    static func routes(for site: CaddySite) -> [JSONValue] {
        Set(site.publicHosts.map(\.hostname)).sorted().map { hostname in
            [
                "match": [["header": ["X-Forwarded-Host": [.string(hostname)]]]],
                "handle": [["handler": "headers", "request": ["set": ["Host": [.string(hostname)]]]]],
            ]
        }
    }
}

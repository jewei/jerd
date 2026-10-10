import JerdFoundation

/// Restores a site's saved public hostname as the request Host, so PHP builds public URLs.
///
/// The routes come first in the site's subroute and are not terminal. Caddy has already matched
/// the TLS server name and the `.test` Host to this site. Only an exact `X-Forwarded-Host` of this
/// site matches, and Caddy sets the saved literal, never the header value. Every other request
/// keeps its `.test` Host.
enum ForwardedHostRoutePolicy {
    static func routes(for site: CaddySite) -> [JSONValue] {
        site.forwardedHosts.map { hostname in
            [
                "match": [["header": ["X-Forwarded-Host": [.string(hostname.value)]]]],
                "handle": [["handler": "headers", "request": ["set": ["Host": [.string(hostname.value)]]]]],
            ]
        }
    }
}

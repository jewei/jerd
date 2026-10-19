import Foundation
import JerdFoundation

/// Renders the Caddy JSON of a run. There is no Caddyfile.
///
/// Invariants of the output: the admin API is off; no ACME, only the internal issuer of the
/// run's CA with `install_trust: false`; loopback or inherited listeners only; no HTTP/3; TLS on
/// every HTTPS connection; strict SNI and Host; unknown hosts get 421 on both servers; HTTP for a
/// known host or alias gets 308 to HTTPS on the same name with the full request URI. A site's
/// aliases share its route. Within a matched site, only an exact
/// `X-Forwarded-Host` of its forwarded hosts replaces the Host, with the saved name
/// (`ForwardedHostRoutePolicy`). The output is deterministic.
package enum CaddyConfigRenderer {
    /// Apple's pretty format with sorted keys and unescaped slashes, as the old generator wrote.
    static let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    /// - Throws: `.invalid` for 0 or more than 256 names, duplicate hostnames, invalid ports, or a
    ///   document root with braces.
    package static func render(
        sites: [CaddySite], authority: LocalAuthority, storage: URL, binding: ListenerBinding
    ) throws -> Data {
        let hostnames = try HostnamePolicy.validateSet(sites.flatMap { $0.servedHostnames.map(\.value) })
        try requireValid(binding)
        let ordered = sites.sorted { $0.hostname < $1.hostname }
        let routes = try siteRoutes(ordered, binding: binding)
        let document: JSONValue = [
            "admin": ["disabled": true],
            "storage": storageValue(storage),
            "apps": [
                "pki": pki(authority, storage: storage),
                "tls": tls(hostnames: hostnames, authority: authority),
                "http": http(binding, secure: routes.secure, redirects: routes.redirects),
            ],
        ]
        return try document.serialized(options)
    }

    /// Each site gets an HTTPS route for all its names and an HTTP redirect for each name; both
    /// servers end with a 421 fallback.
    private static func siteRoutes(
        _ ordered: [CaddySite], binding: ListenerBinding
    ) throws -> (secure: [JSONValue], redirects: [JSONValue]) {
        var secure: [JSONValue] = []
        var redirects: [JSONValue] = []
        for site in ordered {
            let names = site.servedHostnames
            secure.append([
                "match": [["host": .array(names.map { .string($0.value) })]], "terminal": true,
                "handle": [
                    [
                        "handler": "subroute",
                        "routes": .array(
                            ForwardedHostRoutePolicy.routes(for: site) + (try SiteRoutePolicy.routes(for: site))),
                    ]
                ],
            ])
            for name in names {
                redirects.append([
                    "match": [["host": [.string(name.value)]]],
                    "handle": [redirect(to: name, httpsPort: binding.httpsPort)],
                ])
            }
        }
        secure.append(["handle": [SiteRoutePolicy.response(421)]])
        redirects.append(["handle": [SiteRoutePolicy.response(421)]])
        return (secure, redirects)
    }

    private static func requireValid(_ binding: ListenerBinding) throws {
        guard binding.httpsPort > 0, binding.httpPort > 0, binding.httpsPort != binding.httpPort,
            binding.inherited || (binding.httpsPort > 1023 && binding.httpPort > 1023)
        else { throw JerdError.invalid("Standard ports require approved, inherited loopback sockets.") }
    }

    private static func redirect(to hostname: Hostname, httpsPort: UInt16) -> JSONValue {
        let port = httpsPort == 443 ? "" : ":\(httpsPort)"
        return [
            "handler": "static_response", "status_code": 308,
            "headers": ["Location": [.string("https://\(hostname.value)\(port){http.request.uri}")]],
        ]
    }

    private static func http(_ binding: ListenerBinding, secure: [JSONValue], redirects: [JSONValue]) -> JSONValue {
        [
            "http_port": .integer(Int(binding.httpPort)), "https_port": .integer(Int(binding.httpsPort)),
            "servers": [
                "https": [
                    "listen": [.string(binding.httpsAddress)], "protocols": ["h1", "h2"], "strict_sni_host": true,
                    "automatic_https": ["disable_redirects": true], "tls_connection_policies": [[:]],
                    "routes": .array(secure),
                ],
                "http": [
                    "listen": [.string(binding.httpAddress)], "protocols": ["h1"],
                    "automatic_https": ["disable": true], "routes": .array(redirects),
                ],
            ],
        ]
    }

    /// The CA of the run. A CA that Jerd makes is loaded from its root and key; Caddy then makes
    /// only the intermediate. A CA that Caddy made stays in Caddy's storage.
    static func pki(_ authority: LocalAuthority, storage: URL) -> JSONValue {
        let name = JSONValue.string(authority.name)
        var entry: [String: JSONValue] = ["name": name, "root_common_name": name, "install_trust": false]
        if authority.providesRoot {
            entry["root"] = [
                "certificate": .string(authority.rootCertificate(in: storage).path),
                "private_key": .string(authority.rootKey(in: storage).path), "format": "pem_file",
            ]
        }
        return ["certificate_authorities": [authority.id: .object(entry)]]
    }

    private static func tls(hostnames: [Hostname], authority: LocalAuthority) -> JSONValue {
        [
            "automation": [
                "policies": [
                    [
                        "subjects": .array(hostnames.map { .string($0.value) }),
                        "issuers": [["module": "internal", "ca": .string(authority.id)]],
                    ]
                ]
            ]
        ]
    }

    static func storageValue(_ storage: URL) -> JSONValue {
        ["module": "file_system", "root": .string(storage.path)]
    }
}

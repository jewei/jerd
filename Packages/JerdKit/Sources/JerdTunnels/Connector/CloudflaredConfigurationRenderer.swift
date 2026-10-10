import Foundation

/// Renders the private `config.yml` of one launch: one exact public hostname and a final 404 rule,
/// or `{}` for a route from the Cloudflare dashboard.
///
/// The file is JSON, which is valid YAML, so JSON quoting keeps every path and address as data.
/// Slashes stay unescaped, because `\/` is not an escape in YAML 1.1.
package enum CloudflaredConfigurationRenderer {
    /// The rule for every other hostname of the tunnel.
    static let fallbackService = "http_status:404"

    package static func render(_ route: TunnelRoute) throws -> Data {
        let rule: IngressRule
        switch route {
        case .cloudflare:
            return CloudflaredCommand.emptyConfiguration
        case .site(let hostname, let site):
            rule = IngressRule(hostname: hostname.value, service: site.service, originRequest: OriginRequest(site))
        case .address(let hostname, let origin):
            rule = IngressRule(hostname: hostname.value, service: origin, originRequest: nil)
        }
        let document = Ingress(ingress: [
            rule, IngressRule(hostname: nil, service: fallbackService, originRequest: nil),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document) + Data("\n".utf8)
    }

    /// The cloudflared keys as properties, so a misspelled key does not compile.
    private struct Ingress: Encodable {
        let ingress: [IngressRule]
    }

    private struct IngressRule: Encodable {
        let hostname: String?
        let service: String
        let originRequest: OriginRequest?
    }

    /// The site's own name for Host and TLS, checked against the installation CA. Verification
    /// stays on: this value is never omitted for a site.
    private struct OriginRequest: Encodable {
        let httpHostHeader: String
        let originServerName: String
        let caPool: String
        let noTLSVerify = false

        init(_ site: TunnelSiteDestination) {
            httpHostHeader = site.hostname.value
            originServerName = site.hostname.value
            caPool = site.certificateAuthorityFile.path
        }
    }
}

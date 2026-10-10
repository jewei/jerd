import Foundation
import JerdFoundation
import JerdTunnels
import Testing

@Suite struct CloudflaredConfigurationRendererTests {
    private let publicHostname = PublicHostname("shop.example.com")!

    private func site(
        port: UInt16 = 443, caPath: String = "/data root/certificates/root.crt"
    ) throws
        -> TunnelSiteDestination
    {
        TunnelSiteDestination(
            siteID: UUID(), hostname: try Hostname("shop.test"), httpsPort: port,
            certificateAuthorityFile: URL(fileURLWithPath: caPath))
    }

    /// The exact file: one rule for the public hostname with verified TLS, then 404 for the rest.
    @Test func aSiteRouteHasTheExactBytes() throws {
        let rendered = try CloudflaredConfigurationRenderer.render(.site(publicHostname, try site()))
        #expect(String(decoding: rendered, as: UTF8.self) == Self.siteGolden)
    }

    @Test func aSiteRouteSendsTheTestNameAndVerifiesItWithTheInstallationCA() throws {
        let rules = try rules(CloudflaredConfigurationRenderer.render(.site(publicHostname, try site())))
        #expect(rules.count == 2)
        #expect(rules[0]["hostname"] as? String == "shop.example.com")
        #expect(rules[0]["service"] as? String == "https://127.0.0.1:443")
        let origin = try #require(rules[0]["originRequest"] as? [String: Any])
        #expect(origin["httpHostHeader"] as? String == "shop.test")
        #expect(origin["originServerName"] as? String == "shop.test")
        #expect(origin["caPool"] as? String == "/data root/certificates/root.crt")
        #expect(origin["noTLSVerify"] as? Bool == false)
        #expect(rules[1].keys.sorted() == ["service"])
        #expect(rules[1]["service"] as? String == "http_status:404")
    }

    @Test(arguments: ["http://127.0.0.1:8000", "https://localhost:8443", "http://[::1]:8080"])
    func anAddressRouteSendsOnlyThePublicHostnameToTheAddress(_ address: String) throws {
        let rules = try rules(CloudflaredConfigurationRenderer.render(.address(publicHostname, origin: address)))
        #expect(rules[0].keys.sorted() == ["hostname", "service"])
        #expect(rules[0]["hostname"] as? String == "shop.example.com")
        #expect(rules[0]["service"] as? String == address)
        #expect(rules[1]["service"] as? String == "http_status:404")
    }

    @Test func aCloudflareRouteIsAnEmptyConfiguration() throws {
        #expect(try CloudflaredConfigurationRenderer.render(.cloudflare) == Data("{}\n".utf8))
    }

    /// JSON quoting keeps a path with quotes and a backslash as one string, not YAML syntax.
    @Test func aCertificatePathWithQuotesStaysOneString() throws {
        let path = "/data/quoted \"CA\" \\ #: -/root.crt"
        let rules = try rules(CloudflaredConfigurationRenderer.render(.site(publicHostname, try site(caPath: path))))
        let origin = try #require(rules[0]["originRequest"] as? [String: Any])
        #expect(origin["caPool"] as? String == path)
    }

    @Test func theHTTPSPortComesFromTheDestination() throws {
        let rules = try rules(CloudflaredConfigurationRenderer.render(.site(publicHostname, try site(port: 18_443))))
        #expect(rules[0]["service"] as? String == "https://127.0.0.1:18443")
    }

    private func rules(_ data: Data) throws -> [[String: Any]] {
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(document["ingress"] as? [[String: Any]])
    }

    static let siteGolden = """
        {
          "ingress" : [
            {
              "hostname" : "shop.example.com",
              "originRequest" : {
                "caPool" : "/data root/certificates/root.crt",
                "httpHostHeader" : "shop.test",
                "noTLSVerify" : false,
                "originServerName" : "shop.test"
              },
              "service" : "https://127.0.0.1:443"
            },
            {
              "service" : "http_status:404"
            }
          ]
        }

        """
}

import Foundation
import JerdFoundation
import JerdTunnels
import Testing

@Suite struct CloudflaredConfigurationTests {
    private let site = TunnelSiteDestination(
        hostname: "shop.test", certificateAuthority: URL(fileURLWithPath: "/data root/certificates/root.crt"))

    @Test func aLinkedSiteUsesLoopbackWithTheCorrectHostAndVerifiedTLS() throws {
        let registration = TunnelRegistration(
            name: "Shop", hostname: "shop.example.com", siteID: UUID(), routing: .local)
        let rules = try rules(CloudflaredConfiguration.render(registration, site: site))
        #expect(rules.count == 2)
        #expect(rules[0]["hostname"] as? String == "shop.example.com")
        #expect(rules[0]["service"] as? String == "https://127.0.0.1:443")
        let tls = try #require(rules[0]["originRequest"] as? [String: Any])
        #expect(tls["httpHostHeader"] as? String == "shop.test")
        #expect(tls["originServerName"] as? String == "shop.test")
        #expect(tls["caPool"] as? String == site.certificateAuthority.path)
        #expect(tls["noTLSVerify"] as? Bool == false)
        #expect(rules[1]["hostname"] == nil)
        #expect(rules[1]["service"] as? String == "http_status:404")
    }

    @Test(arguments: ["http://127.0.0.1:8000", "https://localhost:8443", "http://[::1]:8080"])
    func aLocalAddressGetsOnlyTheNamedPublicRoute(_ address: String) throws {
        let registration = TunnelRegistration(
            name: "Local", hostname: "local.example.com", originURL: address, routing: .local)
        let rules = try rules(CloudflaredConfiguration.render(registration))
        #expect(rules[0]["service"] as? String == address)
        #expect(rules[0]["hostname"] as? String == registration.hostname)
        #expect(rules[0]["originRequest"] == nil)
        #expect(rules[1]["service"] as? String == "http_status:404")
    }

    @Test func cloudflareRoutingKeepsAnEmptyConfigEvenWithALinkedSite() throws {
        let registration = TunnelRegistration(name: "Remote", hostname: "remote.example.com", siteID: UUID())
        #expect(try CloudflaredConfiguration.render(registration, site: site) == Data("{}\n".utf8))
    }

    @Test func aMissingLinkedSiteCannotProduceAnEmptyOrFallbackRoute() {
        let registration = TunnelRegistration(
            name: "Shop", hostname: "shop.example.com", siteID: UUID(), routing: .local)
        #expect(throws: JerdError.self) { try CloudflaredConfiguration.render(registration) }
    }

    @Test(arguments: [nil, "http://127.0.0.1:8000/path", "http://127.0.0.1:8000?key=value"] as [String?])
    func localRoutingRequiresAnAddressWithoutAPathOrQuery(_ address: String?) {
        let registration = TunnelRegistration(
            name: "Local", hostname: "local.example.com", originURL: address, routing: .local)
        #expect(throws: JerdError.self) { try CloudflaredConfiguration.render(registration) }
        var earlier = registration
        earlier.routing = .cloudflare
        #expect(throws: Never.self) { try earlier.validate() }
    }

    @Test func aCertificatePathIsEncodedAsDataRatherThanYAML() throws {
        let destination = TunnelSiteDestination(
            hostname: "shop.test", certificateAuthority: URL(fileURLWithPath: "/data/quoted \"CA\"/root.crt"))
        let registration = TunnelRegistration(
            name: "Shop", hostname: "shop.example.com", siteID: UUID(), routing: .local)
        let rules = try rules(CloudflaredConfiguration.render(registration, site: destination))
        let tls = try #require(rules[0]["originRequest"] as? [String: Any])
        #expect(tls["caPool"] as? String == destination.certificateAuthority.path)
    }

    private func rules(_ data: Data) throws -> [[String: Any]] {
        let document = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(document["ingress"] as? [[String: Any]])
    }
}

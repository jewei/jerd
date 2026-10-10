import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

/// The forwarded-host routes change the Host that PHP sees, so the default tests check them
/// in the rendered Caddy JSON, not only in the opt-in integration test.
@Suite struct ForwardedHostRoutePolicyTests {
    private func render(app hosts: [String]) throws -> [[NSDictionary]] {
        let sites = [
            CaddySite(
                hostname: try Hostname("app.test"), projectPath: "/p/app", documentRoot: "/p/app/public",
                socket: URL(fileURLWithPath: "/tmp/jerd-run/php-0.sock"),
                forwardedHosts: hosts.compactMap(PublicHostname.init)),
            CaddySite(
                hostname: try Hostname("blog.test"), projectPath: "/p/blog", documentRoot: "/p/blog",
                socket: URL(fileURLWithPath: "/tmp/jerd-run/php-0.sock")),
        ]
        let data = try CaddyConfigRenderer.render(
            sites: sites, authority: .isolatedTest, storage: CaddySamples.storage, binding: .product)
        let config = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let routes = try #require(config.value(forKeyPath: "apps.http.servers.https.routes") as? [NSDictionary])
        return routes.compactMap { route in
            ((route["handle"] as? [NSDictionary])?.first?["routes"] as? [NSDictionary])
        }
    }

    private func restore(_ hostname: String) -> NSDictionary {
        [
            "match": [["header": ["X-Forwarded-Host": [hostname]]]],
            "handle": [["handler": "headers", "request": ["set": ["Host": [hostname]]]]],
        ]
    }

    @Test func forwardedHostRoutesComeFirstInTheSiteSubrouteAndAreSorted() throws {
        let app = try render(app: ["z.example.com", "a.example.com"])[0]
        #expect(app[0] == restore("a.example.com"))
        #expect(app[1] == restore("z.example.com"))
        #expect(app[0]["terminal"] == nil && app[1]["terminal"] == nil)
        let health = try #require(app[2]["match"] as? [NSDictionary])
        #expect(health.first?["path"] as? [String] == [SiteRoutePolicy.healthPath])
    }

    @Test func forwardedHostsOfAnotherSiteNeverEnterThisSiteSubroute() throws {
        let blog = try render(app: ["a.example.com"])[1]
        let health = try #require(blog[0]["match"] as? [NSDictionary])
        #expect(health.first?["path"] as? [String] == [SiteRoutePolicy.healthPath])
        #expect(!blog.contains { ($0["match"] as? [NSDictionary])?.first?["header"] != nil })
    }
}

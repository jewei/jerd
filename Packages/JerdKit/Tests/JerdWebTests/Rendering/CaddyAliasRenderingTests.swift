import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct CaddyAliasRenderingTests {
    private func render() throws -> NSDictionary {
        let site = CaddySite(
            hostname: try Hostname("app.test"), projectPath: "/p/app", documentRoot: "/p/app/public",
            socket: URL(fileURLWithPath: "/tmp/jerd-test/php-0.sock"), forwardedHosts: [],
            aliases: [try Hostname("b.app.test"), try Hostname("a.app.test")])
        let data = try CaddyConfigRenderer.render(
            sites: [site], authority: .isolatedTest, storage: CaddySamples.storage, binding: .product)
        return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    @Test func theSiteRouteMatchesTheHostnameAndEveryAlias() throws {
        let routes = try #require(try render().value(forKeyPath: "apps.http.servers.https.routes") as? [NSDictionary])
        let hosts = routes[0].value(forKeyPath: "match.host") as? [[String]]
        #expect(hosts == [["app.test", "a.app.test", "b.app.test"]])
        #expect(routes.count == 2)
    }

    @Test func eachNameRedirectsToHTTPSOnTheSameName() throws {
        let routes = try #require(try render().value(forKeyPath: "apps.http.servers.http.routes") as? [NSDictionary])
        let locations = routes.dropLast().compactMap {
            ($0.value(forKeyPath: "handle.headers.Location") as? [[String]])?.first?.first
        }
        #expect(
            locations == [
                "https://app.test{http.request.uri}", "https://a.app.test{http.request.uri}",
                "https://b.app.test{http.request.uri}",
            ])
    }

    @Test func theCertificatesCoverEveryAlias() throws {
        let policies = try #require(try render().value(forKeyPath: "apps.tls.automation.policies") as? [NSDictionary])
        #expect(policies[0]["subjects"] as? [String] == ["a.app.test", "app.test", "b.app.test"])
    }
}

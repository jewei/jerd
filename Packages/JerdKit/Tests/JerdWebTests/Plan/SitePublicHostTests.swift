import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SitePublicHostTests {
    @Test(arguments: [
        "https://public.example", "*.example.com", "public.example:443", "{http.request.host}",
        "public.example\r\nHost: other.example", "localhost", "app.localhost", "127.0.0.1", "UPPER.example",
        "example", "public..example", "-public.example", "public-.example", " public.example",
        String(repeating: "a", count: 64) + ".example",
        Array(repeating: String(repeating: "a", count: 63), count: 4).joined(separator: "."),
    ])
    func onlyExactDNSHostnamesCanReachTheHeaderHandler(_ hostname: String) {
        #expect(throws: JerdError.self) { try SitePublicHost(siteID: UUID(), hostname: hostname) }
    }

    @Test func changingATunnelHostChangesTheServingPlanButUnrelatedSitesDoNot() throws {
        let site = Samples.site(URL(fileURLWithPath: "/project"))
        let planned = PlannedSite(site: site, runtime: Samples.runtime())
        let local = ServingPlan(sites: [planned], caddy: Samples.caddy())
        let routed = ServingPlan(
            sites: [planned], caddy: Samples.caddy(),
            publicHosts: [
                try SitePublicHost(siteID: site.id, hostname: "public.example.com")
            ])
        #expect(!local.isEquivalent(to: routed))
        let unrelated = ServingPlan(
            sites: [planned], caddy: Samples.caddy(),
            publicHosts: [
                try SitePublicHost(siteID: UUID(), hostname: "other.example.com")
            ])
        #expect(local.isEquivalent(to: unrelated))
    }
}

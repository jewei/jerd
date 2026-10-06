import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct CaddyConfigRendererTests {
    @Test func theInheritedOutputMatchesItsGoldenFile() throws {
        #expect(try CaddySamples.appendixOutput() == (try Fixture.data("caddy/caddy-inherited.json")))
    }

    @Test func theLoopbackOutputMatchesItsGoldenFile() throws {
        #expect(try CaddySamples.loopbackOutput() == (try Fixture.data("caddy/caddy-loopback.json")))
    }

    /// Appendix A is the output of the old generator. The new output differs only by the fixes
    /// that `AppendixFixes` names: spec B 7.1.1 and 7.1.2, and review web-r1 C1, M1, and L1.
    @Test func theOldAppendixOutputChangesOnlyByTheDocumentedFixes() throws {
        let expected = try #require(
            try JSONSerialization.jsonObject(
                with: Fixture.data("caddy/appendix-a-old.json"), options: [.mutableContainers]) as? NSMutableDictionary)
        let new = try #require(try JSONSerialization.jsonObject(with: CaddySamples.appendixOutput()) as? NSDictionary)
        let newRoutes = try Self.siteRoutes(new)
        let oldRoutes = try Self.siteRoutes(expected).compactMap { $0 as? NSMutableArray }
        #expect(oldRoutes.count == 2 && newRoutes.count == 2)
        for (index, routes) in oldRoutes.enumerated() {
            try AppendixFixes.apply(to: routes, wellKnown: newRoutes[index][2])
        }
        #expect(expected == new)
    }

    @Test func outputIsDeterministicAndIndependentOfSiteOrder() throws {
        let sites = try CaddySamples.appendixSites()
        let forward = try CaddyConfigRenderer.render(
            sites: sites, authority: .isolatedTest, storage: CaddySamples.storage, binding: .product)
        let backward = try CaddyConfigRenderer.render(
            sites: sites.reversed(), authority: .isolatedTest, storage: CaddySamples.storage, binding: .product)
        #expect(forward == backward)
    }

    @Test func theAuthorityNamesTheInstallationOrTheIsolatedCA() throws {
        let sites = try CaddySamples.appendixSites()
        let isolated = String(
            decoding: try CaddyConfigRenderer.render(
                sites: sites, authority: .isolatedTest, storage: CaddySamples.storage, binding: .product), as: UTF8.self
        )
        #expect(isolated.contains("\"jerd-test\" : {") && isolated.contains("Jerd isolated test CA"))
        let installed = String(decoding: try CaddySamples.appendixOutput(), as: UTF8.self)
        #expect(installed.contains("\"jerd\" : {"))
        #expect(installed.contains("Jerd Local CA 11111111-2222-3333-4444-555555555555"))
        #expect(!installed.contains("acme") && installed.contains("\"install_trust\" : false"))
    }

    @Test(arguments: [
        ListenerBinding(httpsPort: 443, httpPort: 80, inherited: false),
        ListenerBinding(httpsPort: 18_443, httpPort: 1_023, inherited: false),
        ListenerBinding(httpsPort: 0, httpPort: 18_080, inherited: true),
        ListenerBinding(httpsPort: 18_443, httpPort: 18_443, inherited: true),
    ])
    func invalidPortsAreRefused(_ binding: ListenerBinding) throws {
        let sites = try CaddySamples.appendixSites()
        #expect(throws: JerdError.invalid("Standard ports require approved, inherited loopback sockets.")) {
            try CaddyConfigRenderer.render(
                sites: sites, authority: .isolatedTest, storage: CaddySamples.storage, binding: binding)
        }
    }

    @Test func emptyOversizedAndDuplicateHostSetsAreRefused() throws {
        let site = try CaddySamples.appendixSites()[0]
        let render = { (sites: [CaddySite]) in
            try CaddyConfigRenderer.render(
                sites: sites, authority: .isolatedTest, storage: CaddySamples.storage, binding: .product)
        }
        #expect(throws: JerdError.invalid("Select between 1 and 256 site hostnames for HTTPS setup.")) {
            try render([])
        }
        #expect(throws: JerdError.invalid("Select between 1 and 256 site hostnames for HTTPS setup.")) {
            try render(
                (0...256).map {
                    CaddySite(
                        hostname: try Hostname("s\($0).test"), projectPath: "/p", documentRoot: "/p",
                        socket: site.socket)
                })
        }
        #expect(throws: JerdError.invalid("Each site needs a unique hostname.")) { try render([site, site]) }
    }

    @Test(arguments: ["/p/{x}", "/p/a}b"])
    func bracesInADocumentRootAreRefused(_ root: String) throws {
        let site = CaddySite(
            hostname: try Hostname("a.test"), projectPath: "/p", documentRoot: root,
            socket: URL(fileURLWithPath: "/tmp/s.sock"))
        #expect(throws: JerdError.invalid("Jerd does not support braces in document-root paths.")) {
            try CaddyConfigRenderer.render(
                sites: [site], authority: .isolatedTest, storage: CaddySamples.storage, binding: .product)
        }
    }

    @Test func thePreparationFileHoldsOnlyThePKIAppWithEscapedSlashes() throws {
        let data = try CaddyConfigRenderer.renderAuthorityPreparation(
            authority: .installation(CaddySamples.installationID), storage: CaddySamples.storage)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\\/Users\\/u"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let name = "Jerd Local CA 11111111-2222-3333-4444-555555555555"
        let expected: NSDictionary = [
            "admin": ["disabled": true],
            "storage": ["module": "file_system", "root": CaddySamples.storage.path],
            "apps": [
                "pki": [
                    "certificate_authorities": [
                        "jerd": ["name": name, "root_common_name": name, "install_trust": false]
                    ]
                ]
            ],
        ]
        #expect(object == expected)
    }

    /// The application route lists of every HTTPS host route, in host order.
    private static func siteRoutes(_ config: NSDictionary) throws -> [NSArray] {
        let routes = try #require(config.value(forKeyPath: "apps.http.servers.https.routes") as? NSArray)
        return routes.compactMap { route in
            ((route as? NSDictionary)?["handle"] as? NSArray)?.compactMap {
                ($0 as? NSDictionary)?["routes"] as? NSArray
            }
            .first
        }
    }
}

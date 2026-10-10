import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite(.enabled(if: IntegrationRun.enabled, "Set JERD_WEB_INTEGRATION=1 and select PHP CLI, PHP-FPM, and Caddy."))
struct TunnelHostIntegrationTests {
    @Test func tunnelPagesUsePublicAssetURLsAndLocalPagesKeepTheirOwnHost() async throws {
        let folder = try TemporaryDirectory(" tunnel host")
        defer { folder.remove() }
        let project = try folder.folder("site")
        try folder.file(
            "site/index.php",
            #"""
            <?php
            if ($_SERVER['REQUEST_URI'] === '/redirect') {
                header('Location: https://'.$_SERVER['HTTP_HOST'].'/destination');
                exit;
            }
            header('Content-Type: application/json');
            echo json_encode([
                'asset' => 'https://'.$_SERVER['HTTP_HOST'].'/app.js',
                'host' => $_SERVER['HTTP_HOST'],
                'server' => $_SERVER['SERVER_NAME'],
                'forwarded' => $_SERVER['HTTP_X_FORWARDED_HOST'] ?? null,
            ]);
            """#)
        try folder.file("site/app.js", "document.body.textContent = 'tunnel works';")
        let runtime = try await IntegrationRun.runtime(in: folder)
        let caddy = try await IntegrationRun.caddy(in: folder)
        let site = Samples.site(project, hostname: "tunnel.test")
        let otherProject = folder.path("other")
        try FileManager.default.copyItem(at: project, to: otherProject)
        let other = Samples.site(otherProject, hostname: "other.test")
        let publicHost = try SitePublicHost(siteID: site.id, hostname: "public.example.com")
        let secondHost = try SitePublicHost(siteID: site.id, hostname: "second.example.com")
        let plan = ServingPlan(
            sites: [site, other].map { PlannedSite(site: $0, runtime: runtime) }, caddy: caddy,
            publicHosts: [publicHost, secondHost])
        let layout = IntegrationRun.layout(in: folder)
        let ports = try IntegrationRun.freePorts()
        let binding = ListenerBinding(httpsPort: ports.https, httpPort: ports.http, inherited: false)
        let engine = EngineRunner()
        do {
            _ = try await engine.start(plan, layout: layout, binding: binding, listeners: nil)
            for (local, forwarded, expected) in [
                (site.hostname, publicHost.hostname, publicHost.hostname),
                (site.hostname, secondHost.hostname, secondHost.hostname),
                (site.hostname, "", "\(site.hostname):\(ports.https)"),
                (site.hostname, "unregistered.example.com", "\(site.hostname):\(ports.https)"),
                (other.hostname, publicHost.hostname, "\(other.hostname):\(ports.https)"),
                (site.hostname, "public.example.com.evil.invalid", "\(site.hostname):\(ports.https)"),
            ] {
                let response = try await IntegrationRun.request(
                    local, "/", port: ports.https, layout: layout,
                    extra: forwarded.isEmpty ? [] : ["--header", "X-Forwarded-Host: \(forwarded)"])
                #expect(response.code.hasPrefix("200"))
                let page = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: String])
                #expect(page["host"] == expected)
                #expect(page["asset"] == "https://\(expected)/app.js")
                #expect(page["forwarded"] == expected)
                #expect(page["server"] == expected.split(separator: ":").first.map(String.init))
            }
            let asset = try await IntegrationRun.request(
                site.hostname, "/app.js", port: ports.https, layout: layout,
                extra: ["--header", "X-Forwarded-Host: \(publicHost.hostname)"])
            #expect(asset.code.hasPrefix("200"))
            #expect(asset.body == Data("document.body.textContent = 'tunnel works';".utf8))
            let redirect = try await IntegrationRun.request(
                site.hostname, "/redirect", port: ports.https, layout: layout,
                extra: ["--include", "--header", "X-Forwarded-Host: \(publicHost.hostname)"])
            #expect(redirect.code.hasPrefix("302"))
            #expect(
                String(decoding: redirect.body, as: UTF8.self).lowercased().contains(
                    "location: https://public.example.com/destination"))
            let wrongHost = try await IntegrationRun.request(
                site.hostname, "/", port: ports.https, layout: layout,
                extra: ["--header", "Host: unknown.test", "--header", "X-Forwarded-Host: \(publicHost.hostname)"])
            #expect(wrongHost.code.hasPrefix("421"))
            await engine.stop()
        } catch {
            await engine.stop()
            throw error
        }
    }
}

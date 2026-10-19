import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite(.enabled(if: IntegrationRun.enabled, "Set JERD_WEB_INTEGRATION=1 and select PHP CLI, PHP-FPM, and Caddy."))
struct ConstrainedCAIntegrationTests {
    /// Caddy loads the CA that Jerd makes, makes its intermediate, and serves a `.test` site with
    /// verified HTTPS. The CA stays in the temporary folder, and no trust store changes.
    @Test func caddyServesATestSiteWithTheJerdMadeCA() async throws {
        let folder = try TemporaryDirectory(" constrained ca")
        defer { folder.remove() }
        let project = try folder.folder("site")
        try folder.file("site/index.php", "<?php echo 'served-with-the-jerd-ca';")
        let id = UUID()
        let layout = IntegrationRun.layout(in: folder, authority: .constrainedInstallation(id))
        let authority = try LocalCAProvisioner(environment: layout.environment).provision(installationID: id)
        let key = contents(layout.environment.constrainedRootKeyFile)
        let site = Samples.site(project, hostname: "constrained-ca.test")
        let plan = ServingPlan(
            sites: [PlannedSite(site: site, runtime: try await IntegrationRun.runtime(in: folder))],
            caddy: try await IntegrationRun.caddy(in: folder))
        let listeners = try TestListeners()
        defer { listeners.close() }
        let engine = EngineRunner()
        _ = try await engine.start(
            plan, layout: layout,
            binding: ListenerBinding(httpsPort: listeners.httpsPort, httpPort: listeners.httpPort, inherited: true),
            listeners: listeners.inherited)
        let response = try? await IntegrationRun.request(site.hostname, "/", port: listeners.httpsPort, layout: layout)
        await engine.stop()
        #expect(response?.code.hasPrefix("200") == true)
        #expect(response.map { String(decoding: $0.body, as: UTF8.self) } == "served-with-the-jerd-ca")
        #expect(try LocalCertificateAuthority.read(layout.rootCertificateFile) == authority)
        #expect(contents(layout.environment.constrainedRootKeyFile) == key)
        #expect(
            FileProbe.presence(
                at: layout.environment.authorityDirectory("jerd-2").appendingPathComponent("intermediate.crt"))
                == .present)
    }
}

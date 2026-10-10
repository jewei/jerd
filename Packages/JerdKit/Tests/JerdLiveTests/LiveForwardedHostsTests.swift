import Foundation
import JerdFoundation
import JerdTestSupport
import JerdTunnels
import JerdWeb
import Testing

@testable import JerdLive

@Suite struct LiveForwardedHostsTests {
    @Test func savedLocalSiteRoutesBecomeTheForwardedHostsOfTheirSite() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url).tunnels
        let siteID = UUID()
        let port = TunnelRegistration.defaultMetricsPort
        try TunnelStore(layout: layout).save(
            TunnelConfiguration(tunnels: [
                TunnelRegistration(
                    name: "local", hostname: "public.example.com", siteID: siteID, metricsPort: port, routing: .local),
                TunnelRegistration(
                    name: "remote", hostname: "remote.example.com", siteID: siteID, metricsPort: port + 1),
            ]))
        let hosts = try LiveForwardedHosts(layout: layout).loadForwardedHosts()
        #expect(hosts == ForwardedHosts([siteID: [PublicHostname("public.example.com")!]]))
    }

    @Test func corruptTunnelSettingsArePreservedAndReported() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url).tunnels
        try OwnedDirectory.create(layout.root)
        let corrupt = Data("not json".utf8)
        try AtomicFile.write(corrupt, to: layout.settingsFile)
        #expect {
            try LiveForwardedHosts(layout: layout).loadForwardedHosts()
        } throws: { error in
            (error as? JerdError)?.kind == .corrupt
        }
        #expect(contents(layout.settingsFile) == corrupt)
    }
}

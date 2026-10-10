import Foundation
import JerdFoundation
import JerdTestSupport
import JerdTunnels
import JerdWeb
import Testing

@testable import JerdLive

@Suite struct LiveTunnelHostSourceTests {
    @Test func onlySavedLocalSiteRoutesSupplyPublicHostsAndEachReadSeesChanges() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url).tunnels
        let store = TunnelStore(layout: layout)
        let siteID = UUID()
        var local = TunnelRegistration(
            name: "local", hostname: "public.example.com", siteID: siteID, metricsPort: 20241, routing: .local)
        let remote = TunnelRegistration(
            name: "remote", hostname: "remote.example.com", siteID: siteID, metricsPort: 20242)
        let address = TunnelRegistration(
            name: "address", hostname: "address.example.com", originURL: "http://127.0.0.1:8000",
            metricsPort: 20243, routing: .local)
        try store.save(TunnelConfiguration(tunnels: [local, remote, address]))
        let source = LiveTunnelHostSource(layout: layout)
        #expect(try await source.loadPublicHosts() == [SitePublicHost(siteID: siteID, hostname: local.hostname)])
        local.hostname = "renamed.example.com"
        try store.save(TunnelConfiguration(tunnels: [local]))
        #expect(try await source.loadPublicHosts() == [SitePublicHost(siteID: siteID, hostname: local.hostname)])
        try store.save(TunnelConfiguration())
        #expect(try await source.loadPublicHosts().isEmpty)
    }

    @Test func corruptTunnelSettingsArePreservedAndReported() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url).tunnels
        try OwnedDirectory.create(layout.root)
        let corrupt = Data("not json".utf8)
        try AtomicFile.write(corrupt, to: layout.settingsFile)
        let source = LiveTunnelHostSource(layout: layout)
        await #expect(throws: JerdError.self) { try await source.loadPublicHosts() }
        #expect(try Data(contentsOf: layout.settingsFile) == corrupt)
    }
}

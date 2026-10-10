import Foundation
import JerdFoundation
import JerdTestSupport
import JerdTunnels
import Testing

@Suite struct TunnelSiteRoutesTests {
    private let siteID = UUID()

    private func local(
        _ hostname: String, port: UInt16, siteID: UUID? = nil, origin: String? = nil
    )
        -> TunnelRegistration
    {
        TunnelRegistration(
            name: hostname, hostname: hostname, siteID: siteID, originURL: origin, metricsPort: port, routing: .local)
    }

    @Test func onlyLocalRoutesToASiteSupplyPublicHostnames() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let port = TunnelRegistration.defaultMetricsPort
        try TunnelStore(layout: folder.layout).save(
            TunnelConfiguration(tunnels: [
                local("public.example.com", port: port, siteID: siteID),
                local("second.example.com", port: port + 1, siteID: siteID),
                TunnelRegistration(
                    name: "remote", hostname: "remote.example.com", siteID: siteID, metricsPort: port + 2),
                local("address.example.com", port: port + 3, origin: "http://127.0.0.1:8000"),
            ]))
        let routes = try TunnelSiteRoutes(layout: folder.layout).load()
        #expect(routes == [siteID: Set(["public.example.com", "second.example.com"].compactMap(PublicHostname.init))])
    }

    @Test func eachReadSeesTheSavedFileAsItIsNow() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = TunnelStore(layout: folder.layout)
        let routes = TunnelSiteRoutes(layout: folder.layout)
        var tunnel = local("public.example.com", port: TunnelRegistration.defaultMetricsPort, siteID: siteID)
        try store.save(TunnelConfiguration(tunnels: [tunnel]))
        #expect(try routes.load()[siteID] == [PublicHostname("public.example.com")!])
        tunnel.hostname = "renamed.example.com"
        try store.save(TunnelConfiguration(tunnels: [tunnel]))
        #expect(try routes.load()[siteID] == [PublicHostname("renamed.example.com")!])
    }

    @Test func anAbsentSettingsFileHasNoRoutes() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        #expect(try TunnelSiteRoutes(layout: folder.layout).load().isEmpty)
    }

    /// An earlier build could save a value that Save now refuses. That registration cannot
    /// connect, so it supplies no route, and the other routes stay.
    @Test func aRegistrationThatSaveRefusesIsSkippedAndTheOthersStay() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let port = TunnelRegistration.defaultMetricsPort
        try OwnedDirectory.create(folder.layout.root)
        let refused = local("10.0.0.1", port: port, siteID: UUID())
        let valid = local("public.example.com", port: port + 1, siteID: siteID)
        let data = try JSONEncoder().encode(TunnelConfiguration(tunnels: [refused, valid]))
        try AtomicFile.write(data, to: folder.layout.settingsFile)
        #expect(try TunnelSiteRoutes(layout: folder.layout).load() == [siteID: [PublicHostname("public.example.com")!]])
    }

    @Test func corruptSettingsArePreservedAndReported() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try OwnedDirectory.create(folder.layout.root)
        let corrupt = Data("not json".utf8)
        try AtomicFile.write(corrupt, to: folder.layout.settingsFile)
        #expect {
            try TunnelSiteRoutes(layout: folder.layout).load()
        } throws: { error in
            (error as? JerdError)?.kind == .corrupt
        }
        #expect(contents(folder.layout.settingsFile) == corrupt)
    }
}

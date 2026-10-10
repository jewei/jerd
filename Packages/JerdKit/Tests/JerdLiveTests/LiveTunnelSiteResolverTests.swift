import Foundation
import JerdFoundation
import JerdTestSupport
import JerdTunnels
import JerdWeb
import Testing

@testable import JerdLive

@Suite struct LiveTunnelSiteResolverTests {
    private let site = SampleWeb.site()

    /// A data root with the installation CA, so only the site decides the result.
    private func layoutWithCA(_ folder: TemporaryDirectory) throws -> EnvironmentLayout {
        let layout = DataLayout(root: folder.url).environment
        try OwnedDirectory.create(layout.rootCertificateFile.deletingLastPathComponent())
        try AtomicFile.write(Data("fixture certificate".utf8), to: layout.rootCertificateFile)
        return layout
    }

    private func resolver(
        _ sites: FakeForwardedHostApplying, layout: EnvironmentLayout, saved: [Site]? = nil
    )
        -> LiveTunnelSiteResolver
    {
        LiveTunnelSiteResolver(
            sites: sites, registry: FakeSiteRegistry(SampleWeb.configuration(sites: saved ?? [site])), layout: layout)
    }

    @Test func aServedSiteGivesItsTestNameTheHTTPSPortAndTheInstallationCA() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = try layoutWithCA(folder)
        let sites = FakeForwardedHostApplying(serving: site)
        let destination = try await resolver(sites, layout: layout).prepareDestination(for: site.id)
        #expect(
            destination
                == TunnelSiteDestination(
                    siteID: site.id, hostname: try Hostname("shop.test"), httpsPort: 443,
                    certificateAuthorityFile: layout.rootCertificateFile))
        #expect(await sites.requests == [site.id])
    }

    /// The route must use the name that Caddy serves now, not a saved name that a running
    /// site change has not applied yet.
    @Test func theServedHostnameIsUsedInsteadOfTheSavedOne() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var saved = site
        saved.hostname = "renamed.test"
        let destination = try await resolver(
            FakeForwardedHostApplying(serving: site), layout: try layoutWithCA(folder), saved: [saved]
        ).prepareDestination(for: site.id)
        #expect(destination.hostname.value == "shop.test")
    }

    @Test func aRemovedSiteAsksForAnotherDestination() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let resolver = resolver(FakeForwardedHostApplying(), layout: try layoutWithCA(folder), saved: [])
        await #expect(throws: JerdError.unavailable(TunnelMessage.siteRemoved)) {
            try await resolver.prepareDestination(for: site.id)
        }
    }

    @Test func aSiteThatDoesNotRunAsksTheUserToStartIt() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let resolver = resolver(FakeForwardedHostApplying(), layout: try layoutWithCA(folder))
        await #expect(throws: JerdError.unavailable(TunnelMessage.siteNotRunning(site.displayName))) {
            try await resolver.prepareDestination(for: site.id)
        }
    }

    /// Without the CA, cloudflared cannot verify TLS. Jerd never turns verification off, and it
    /// does not restart the sites for a route that cannot work.
    @Test func aMissingCAStopsTheLaunchBeforeTheSitesAreTouched() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let sites = FakeForwardedHostApplying(serving: site)
        let resolver = resolver(sites, layout: DataLayout(root: folder.url).environment)
        await #expect(throws: JerdError.unavailable(TunnelMessage.certificateAuthorityMissing)) {
            try await resolver.prepareDestination(for: site.id)
        }
        #expect(await sites.requests.isEmpty)
    }

    @Test func aFailedApplyStopsTheLaunchWithItsError() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let sites = FakeForwardedHostApplying(serving: site)
        let failure = JerdError.corrupt("Cannot read tunnel settings. The file was preserved.")
        await sites.fail(failure)
        let resolver = resolver(sites, layout: try layoutWithCA(folder))
        await #expect(throws: failure) { try await resolver.prepareDestination(for: site.id) }
    }
}

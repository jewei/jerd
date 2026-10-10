import Foundation
import JerdFoundation
import JerdTestSupport
import JerdWeb
import Testing

@testable import JerdLive

@Suite struct LiveTunnelSiteResolverTests {
    @Test func theSelectedSiteUsesTheInstallationCertificate() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url).environment
        try OwnedDirectory.create(layout.rootCertificateFile.deletingLastPathComponent())
        try AtomicFile.write(Data("fixture certificate".utf8), to: layout.rootCertificateFile)
        let site = SampleWeb.site()
        let environment = FakeEnvironment()
        await environment.setSnapshot(EnvironmentSnapshot(state: .running, siteIDs: [site.id]))
        let resolver = LiveTunnelSiteResolver(
            registry: FakeSiteRegistry(SampleWeb.configuration(sites: [site])), environment: environment, layout: layout
        )
        let destination = try await resolver.destination(for: site.id)
        #expect(destination.hostname == site.hostname)
        #expect(destination.certificateAuthority == layout.rootCertificateFile)
    }

    @Test func aRemovedSiteHasAnActionableError() async throws {
        let resolver = LiveTunnelSiteResolver(
            registry: FakeSiteRegistry(), environment: FakeEnvironment(),
            layout: DataLayout(root: URL(fileURLWithPath: "/unused")).environment)
        await #expect(throws: JerdError.unavailable("The linked site was removed. Edit this tunnel to choose a site."))
        {
            try await resolver.destination(for: UUID())
        }
    }

    @Test func aStoppedSiteCannotStartAConnectorThatHasNoWorkingDestination() async throws {
        let site = SampleWeb.site()
        let resolver = LiveTunnelSiteResolver(
            registry: FakeSiteRegistry(SampleWeb.configuration(sites: [site])), environment: FakeEnvironment(),
            layout: DataLayout(root: URL(fileURLWithPath: "/unused")).environment)
        await #expect(throws: JerdError.unavailable("Start Shop in Sites before connecting this tunnel.")) {
            try await resolver.destination(for: site.id)
        }
    }

    @Test func aMissingCertificateDoesNotDisableTLSVerification() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let site = SampleWeb.site()
        let environment = FakeEnvironment()
        await environment.setSnapshot(EnvironmentSnapshot(state: .running, siteIDs: [site.id]))
        let resolver = LiveTunnelSiteResolver(
            registry: FakeSiteRegistry(SampleWeb.configuration(sites: [site])), environment: environment,
            layout: DataLayout(root: folder.url).environment)
        await #expect(
            throws: JerdError.unavailable(
                "The site's HTTPS certificate is missing. Restart the site before connecting.")
        ) {
            try await resolver.destination(for: site.id)
        }
    }
}

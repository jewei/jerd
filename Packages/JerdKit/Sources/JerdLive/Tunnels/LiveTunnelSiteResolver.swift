import Foundation
import JerdFoundation
import JerdTunnels

/// Uses the current site registration and Jerd's own CA for each local connector launch.
package actor LiveTunnelSiteResolver: TunnelSiteResolving {
    private let registry: any SiteConfigurationLoading
    private let environment: any EnvironmentControlling
    private let layout: EnvironmentLayout

    package init(
        registry: any SiteConfigurationLoading, environment: any EnvironmentControlling, layout: EnvironmentLayout
    ) {
        self.registry = registry
        self.environment = environment
        self.layout = layout
    }

    package func destination(for siteID: UUID) async throws -> TunnelSiteDestination {
        let configuration = try await registry.snapshot()
        guard let site = configuration.sites.first(where: { $0.id == siteID }) else {
            throw JerdError.unavailable("The linked site was removed. Edit this tunnel to choose a site.")
        }
        guard await environment.snapshot().siteIDs.contains(siteID) else {
            throw JerdError.unavailable("Start \(site.displayName) in Sites before connecting this tunnel.")
        }
        guard FileProbe.presence(at: layout.rootCertificateFile) == .present else {
            throw JerdError.unavailable("The site's HTTPS certificate is missing. Restart the site before connecting.")
        }
        try await environment.preparePublicHosts(for: siteID)
        return TunnelSiteDestination(hostname: site.hostname, certificateAuthority: layout.rootCertificateFile)
    }
}

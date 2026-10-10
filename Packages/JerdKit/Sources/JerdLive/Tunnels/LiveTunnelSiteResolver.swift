import Foundation
import JerdFoundation
import JerdTunnels
import JerdWeb

/// Prepares a linked Jerd site for each local connector launch: the site as the web run serves
/// it, with its public hostnames restored, and Jerd's own CA to verify it.
package struct LiveTunnelSiteResolver: TunnelSiteResolving {
    private let sites: any ForwardedHostApplying
    private let registry: any SiteConfigurationLoading
    private let layout: EnvironmentLayout

    package init(sites: any ForwardedHostApplying, registry: any SiteConfigurationLoading, layout: EnvironmentLayout) {
        self.sites = sites
        self.registry = registry
        self.layout = layout
    }

    /// Checks the CA first: without it the route cannot verify TLS, so a restart would be wasted.
    package func prepareDestination(for siteID: UUID) async throws -> TunnelSiteDestination {
        guard FileProbe.presence(at: layout.rootCertificateFile) == .present else {
            throw JerdError.unavailable(TunnelMessage.certificateAuthorityMissing)
        }
        guard let site = try await sites.applyForwardedHosts(servingSite: siteID) else {
            throw try await notServed(siteID)
        }
        return TunnelSiteDestination(
            siteID: siteID, hostname: try Hostname(site.hostname), httpsPort: ListenerBinding.product.httpsPort,
            certificateAuthorityFile: layout.rootCertificateFile)
    }

    /// Why the run does not serve `siteID`: the site was removed, or it does not run.
    private func notServed(_ siteID: UUID) async throws -> JerdError {
        guard let site = try await registry.snapshot().sites.first(where: { $0.id == siteID }) else {
            return .unavailable(TunnelMessage.siteRemoved)
        }
        return .unavailable(TunnelMessage.siteNotRunning(site.displayName))
    }
}

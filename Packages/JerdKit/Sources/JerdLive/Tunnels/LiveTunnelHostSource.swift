import JerdFoundation
import JerdTunnels
import JerdWeb

/// Reads saved local tunnel routes when the web environment prepares a run.
package struct LiveTunnelHostSource: SitePublicHostsLoading {
    private let routes: TunnelSiteRoutes

    package init(layout: TunnelsLayout) {
        routes = TunnelSiteRoutes(layout: layout)
    }

    package func loadPublicHosts() throws -> Set<SitePublicHost> {
        try Set(
            routes.load().flatMap { siteID, hostnames in
                try hostnames.map { try SitePublicHost(siteID: siteID, hostname: $0.value) }
            })
    }
}

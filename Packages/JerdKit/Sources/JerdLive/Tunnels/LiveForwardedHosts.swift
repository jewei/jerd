import JerdFoundation
import JerdTunnels
import JerdWeb

/// Supplies the web run with the public hostnames of the saved local tunnel routes.
package struct LiveForwardedHosts: ForwardedHostsLoading {
    private let routes: TunnelSiteRoutes

    package init(layout: TunnelsLayout) {
        routes = TunnelSiteRoutes(layout: layout)
    }

    package func loadForwardedHosts() throws -> ForwardedHosts {
        ForwardedHosts(try routes.load())
    }
}

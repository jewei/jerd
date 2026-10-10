import JerdFoundation
import JerdTunnels
import JerdWeb

/// Reads saved local tunnel routes when the web environment prepares a run.
package actor LiveTunnelHostSource: SitePublicHostsLoading {
    private let store: TunnelStore

    package init(layout: TunnelsLayout) {
        store = TunnelStore(layout: layout)
    }

    package func loadPublicHosts() throws -> Set<SitePublicHost> {
        let configuration = try store.load()
        return try Set(
            configuration.tunnels.compactMap { tunnel in
                guard tunnel.routing == .local, let siteID = tunnel.siteID else { return nil }
                try tunnel.validate()
                return try SitePublicHost(siteID: siteID, hostname: tunnel.hostname)
            })
    }
}

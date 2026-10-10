import Foundation
import JerdFoundation

/// Reads the public hostnames of saved local routes to Jerd sites, for the web run. It never
/// writes: `TunnelSupervisor` stays the only writer, and atomic saves keep each read complete.
package struct TunnelSiteRoutes: Sendable {
    private let store: TunnelStore

    package init(layout: TunnelsLayout) {
        store = TunnelStore(layout: layout)
    }

    /// The public hostnames by linked site ID, from the file as it is now.
    ///
    /// A registration that Save refuses is skipped, not reported: it cannot connect, and its
    /// tunnel page already asks for an edit. One such registration must not hide the others.
    /// - Throws: `.corrupt` when the file cannot be read. The file stays as it is.
    package func load() throws -> [UUID: Set<PublicHostname>] {
        var routes: [UUID: Set<PublicHostname>] = [:]
        for tunnel in try store.load().tunnels {
            let route: (hostname: PublicHostname, target: TunnelRegistration.LocalTarget)?
            do {
                route = try tunnel.localRoute()
            } catch {
                continue
            }
            guard let route, case .site(let siteID) = route.target else { continue }
            routes[siteID, default: []].insert(route.hostname)
        }
        return routes
    }
}

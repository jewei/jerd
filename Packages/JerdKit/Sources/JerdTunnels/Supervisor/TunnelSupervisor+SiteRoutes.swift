import Foundation

extension TunnelSupervisor {
    /// Stops each connector whose Jerd route goes to a site that the web run no longer serves under
    /// the hostname of its launch. Public traffic then cannot reach another site that takes that
    /// name, or another local server on port 443. The tunnel shows why; Connect starts it again.
    ///
    /// The app calls it after each site change and each Stop. A failed stop shows on its tunnel.
    /// - Parameter served: The `.test` hostname of each site that the web run serves, by site ID.
    package func stopRoutesToUnservedSites(_ served: [UUID: String]) async {
        let stale = configuration.tunnels.filter { tunnel in
            guard tunnel.routing == .local, let siteID = tunnel.siteID else { return false }
            if let site = handles[tunnel.id]?.siteDestination { return served[site.siteID] != site.hostname.value }
            // A launch without a connector yet resolves its site after this change, so only a
            // site that the run does not serve at all stops it.
            return isActive(tunnel.id) && served[siteID] == nil
        }
        await withTaskGroup(of: Void.self) { group in
            for tunnel in stale {
                group.addTask {
                    do {
                        try await self.stop(id: tunnel.id, reason: TunnelMessage.siteRouteStopped)
                    } catch {
                        // The connector stays owned, and its tunnel shows the stop failure.
                    }
                }
            }
        }
    }
}

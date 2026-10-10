import Foundation

extension TunnelSupervisor {
    /// Stops each connector whose Jerd route goes to a site that the web run no longer serves under
    /// the hostname of its launch. Public traffic then cannot reach another site that takes that
    /// name, or another local server on port 443. The tunnel shows why; Connect starts it again.
    ///
    /// The app calls it after each site change and each Stop. A failed stop shows on its tunnel.
    /// - Parameter served: The `.test` hostname of each site that the web run serves, by site ID.
    public func stopRoutesToUnservedSites(_ served: [UUID: String]) async {
        let stale = handles.values.filter { handle in
            guard let site = handle.siteDestination else { return false }
            return served[site.siteID] != site.hostname.value
        }
        await withTaskGroup(of: Void.self) { group in
            for handle in stale {
                group.addTask {
                    do {
                        try await self.stop(id: handle.registrationID, reason: TunnelMessage.siteRouteStopped)
                    } catch {
                        // The connector stays owned, and its tunnel shows the stop failure.
                    }
                }
            }
        }
    }
}

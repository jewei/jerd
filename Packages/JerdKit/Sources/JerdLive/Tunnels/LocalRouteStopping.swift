import Foundation
import JerdTunnels

/// Stops the local tunnel routes whose site the web run no longer serves. `TunnelSupervisor` is
/// the live type.
package protocol LocalRouteStopping: Sendable {
    /// - Parameter served: The `.test` hostname of each site that the web run serves, by site ID.
    func stopRoutesToUnservedSites(_ served: [UUID: String]) async
}

extension TunnelSupervisor: LocalRouteStopping {}

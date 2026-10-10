import Foundation

/// Resolves a linked site at each launch without coupling tunnels to the web module.
public protocol TunnelSiteResolving: Sendable {
    func destination(for siteID: UUID) async throws -> TunnelSiteDestination
}

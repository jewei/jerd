import Foundation

/// Makes a linked Jerd site ready for one connector launch, without coupling tunnels to the web
/// module. JerdLive implements it with the site change transaction.
///
/// A call can restart the shared web run once, when the saved public hostnames changed. It waits
/// for a site change that runs. A `JerdError` means that the user must act, for example start
/// the site.
package protocol TunnelSiteResolving: Sendable {
    func prepareDestination(for siteID: UUID) async throws -> TunnelSiteDestination
}

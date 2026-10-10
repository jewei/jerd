import Foundation
import JerdFoundation

/// The public hostnames that each site restores as its request Host from an exact
/// `X-Forwarded-Host`, by site ID. A forwarder such as a local tunnel sends them. No other value
/// changes the Host, so PHP builds public URLs only for a saved route.
package struct ForwardedHosts: Equatable, Sendable {
    /// No forwarded hosts: every request keeps its `.test` Host.
    package static let none = ForwardedHosts([:])

    private let hostsBySite: [UUID: Set<PublicHostname>]

    /// A site without hosts is dropped, so two equal mappings always compare equal.
    package init(_ hostsBySite: [UUID: Set<PublicHostname>]) {
        self.hostsBySite = hostsBySite.filter { !$0.value.isEmpty }
    }

    /// The hosts of one site, sorted, so the Caddy output is deterministic.
    package func hosts(of siteID: UUID) -> [PublicHostname] {
        (hostsBySite[siteID] ?? []).sorted()
    }

    /// Only the hosts of `siteIDs`: a run forwards nothing to a site that it does not serve.
    package func limited(to siteIDs: Set<UUID>) -> ForwardedHosts {
        ForwardedHosts(hostsBySite.filter { siteIDs.contains($0.key) })
    }
}

import Foundation
import JerdFoundation

/// What one run serves: a set of enabled sites with their runtimes, one Caddy, and the public
/// hostnames that the sites restore from a forwarder.
///
/// The engine starts one Caddy for every hostname and one PHP-FPM master per distinct runtime.
public struct ServingPlan: Equatable, Sendable {
    public let sites: [PlannedSite]
    public let caddy: CaddyRuntime
    /// The forwarded hosts of the planned sites only.
    package let forwardedHosts: ForwardedHosts

    public init(sites: [PlannedSite], caddy: CaddyRuntime) {
        self.init(sites: sites, caddy: caddy, forwardedHosts: .none)
    }

    /// Drops the forwarded hosts of sites outside the plan.
    package init(sites: [PlannedSite], caddy: CaddyRuntime, forwardedHosts: ForwardedHosts) {
        self.sites = sites
        self.caddy = caddy
        self.forwardedHosts = forwardedHosts.limited(to: Set(sites.map(\.site.id)))
    }

    /// The enabled sites of `configuration` (only those in `siteIDs`, when given), in saved order,
    /// without forwarded hosts. The site change transaction adds them with `forwarding(_:)`.
    ///
    /// Only the selected sites resolve a runtime, so a stopped site with a missing pin does not
    /// block a run of the other sites.
    /// - Throws: `.unavailable` when Caddy or a selected runtime is missing.
    public init(_ configuration: AppConfiguration, siteIDs: Set<UUID>? = nil) throws {
        guard let caddy = configuration.caddy else { throw JerdError.unavailable("Caddy is unavailable.") }
        self.caddy = caddy
        forwardedHosts = .none
        sites = try configuration.sites
            .filter { $0.isEnabled && (siteIDs?.contains($0.id) ?? true) }
            .map { PlannedSite(site: $0, runtime: try configuration.runtime(for: $0)) }
    }

    public var isEmpty: Bool { sites.isEmpty }
    public var siteIDs: Set<UUID> { Set(sites.map(\.site.id)) }
    /// The hostnames as saved, in plan order.
    public var hostnames: [String] { sites.map(\.site.hostname) }

    /// The same sites and Caddy with `hosts`, limited to the planned sites.
    package func forwarding(_ hosts: ForwardedHosts) -> ServingPlan {
        ServingPlan(sites: sites, caddy: caddy, forwardedHosts: hosts)
    }

    /// True when both plans serve the same way: the same Caddy record, the same forwarded hosts,
    /// and, for every site ID, the same hostname, paths, and runtime. Site order and display data
    /// do not count.
    public func isEquivalent(to other: ServingPlan) -> Bool {
        guard caddy == other.caddy, sites.count == other.sites.count, forwardedHosts == other.forwardedHosts else {
            return false
        }
        return sites.allSatisfy { entry in
            other.sites.first { $0.site.id == entry.site.id }.map(entry.servesLike) ?? false
        }
    }

    /// Every executable that the run starts: Caddy, and the CLI and FPM of each runtime.
    public var executablePaths: Set<String> {
        Set([caddy.path] + sites.flatMap { [$0.runtime.cliPath, $0.runtime.fpmPath] })
    }
}

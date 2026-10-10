import Foundation
import JerdFoundation

/// What one run serves: a set of enabled sites with their runtimes, and one Caddy.
///
/// The engine starts one Caddy for every hostname and one PHP-FPM master per distinct runtime.
public struct ServingPlan: Equatable, Sendable {
    public let sites: [PlannedSite]
    public let caddy: CaddyRuntime
    public let publicHosts: Set<SitePublicHost>

    public init(sites: [PlannedSite], caddy: CaddyRuntime, publicHosts: Set<SitePublicHost> = []) {
        self.sites = sites
        self.caddy = caddy
        let ids = Set(sites.map(\.site.id))
        self.publicHosts = publicHosts.filter { ids.contains($0.siteID) }
    }

    /// The enabled sites of `configuration` (only those in `siteIDs`, when given), in saved order.
    ///
    /// Only the selected sites resolve a runtime, so a stopped site with a missing pin does not
    /// block a run of the other sites.
    /// - Throws: `.unavailable` when Caddy or a selected runtime is missing.
    public init(_ configuration: AppConfiguration, siteIDs: Set<UUID>? = nil) throws {
        guard let caddy = configuration.caddy else { throw JerdError.unavailable("Caddy is unavailable.") }
        self.caddy = caddy
        publicHosts = []
        sites = try configuration.sites
            .filter { $0.isEnabled && (siteIDs?.contains($0.id) ?? true) }
            .map { PlannedSite(site: $0, runtime: try configuration.runtime(for: $0)) }
    }

    public var isEmpty: Bool { sites.isEmpty }
    public var siteIDs: Set<UUID> { Set(sites.map(\.site.id)) }
    /// The hostnames as saved, in plan order.
    public var hostnames: [String] { sites.map(\.site.hostname) }

    /// True when both plans serve the same way: the same Caddy record and, for every site ID, the
    /// same hostname, paths, and runtime. Site order and display data do not count.
    public func isEquivalent(to other: ServingPlan) -> Bool {
        guard caddy == other.caddy, sites.count == other.sites.count, publicHosts == other.publicHosts else {
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

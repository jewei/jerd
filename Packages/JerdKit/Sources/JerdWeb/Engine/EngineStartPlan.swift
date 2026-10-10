import Foundation
import JerdFoundation
import JerdProcess

/// Everything one engine run writes and starts, computed without side effects.
///
/// One PHP-FPM pool serves each distinct runtime (in plan order); one Caddy serves every site.
struct EngineStartPlan: Sendable {
    /// One pool: its runtime and its files.
    struct Pool: Equatable, Sendable {
        let runtime: DevelopmentRuntime
        let layout: PoolLayout
    }

    let layout: RunLayout
    let binding: ListenerBinding
    let caddy: CaddyRuntime
    let pools: [Pool]
    let caddySites: [CaddySite]

    /// - Parameter sites: the plan's sites after validation, in plan order.
    init(plan: ServingPlan, validatedSites sites: [Site], layout: RunLayout, binding: ListenerBinding) throws {
        let runtimes = try RuntimeDriftCheck.distinctRuntimes(of: plan)
        let pools = runtimes.enumerated().map { index, runtime in
            Pool(runtime: runtime, layout: layout.pool(runtimeID: runtime.id, index: index))
        }
        caddySites = try zip(plan.sites, sites).map { entry, site in
            guard let pool = pools.first(where: { $0.runtime.id == entry.runtime.id }) else {
                throw JerdError.invalid("A site's PHP socket is missing.")
            }
            return CaddySite(
                hostname: try HostnamePolicy.validate(site.hostname), projectPath: site.projectPath,
                documentRoot: site.documentRoot, socket: pool.layout.socket,
                forwardedHosts: plan.forwardedHosts.hosts(of: site.id))
        }
        self.pools = pools
        self.layout = layout
        self.binding = binding
        caddy = plan.caddy
    }

    /// The Caddy JSON of this run.
    func caddyConfiguration() throws -> Data {
        try CaddyConfigRenderer.render(
            sites: caddySites, authority: layout.authority, storage: layout.environment.certificatesDirectory,
            binding: binding)
    }

    /// `php-fpm -c <php.ini> -y <php-fpm.conf> -t`: checks the pool files.
    func fpmTest(_ pool: Pool) -> ProcessRequest { fpm(pool, mode: "-t") }

    /// `php-fpm -c <php.ini> -y <php-fpm.conf> -F`: runs the master in the foreground.
    func fpmLaunch(_ pool: Pool) -> ProcessRequest { fpm(pool, mode: "-F") }

    /// `caddy validate --config <caddy.json>` with the listeners that the run passes.
    func caddyValidation(_ listeners: InheritedListeners?) -> ProcessRequest {
        caddyRequest(["validate", "--config", layout.environment.caddyConfigurationFile.path], listeners)
    }

    /// `caddy run --config <caddy.json>`.
    func caddyLaunch(_ listeners: InheritedListeners?) -> ProcessRequest {
        caddyRequest(["run", "--config", layout.environment.caddyConfigurationFile.path], listeners)
    }

    /// A CA-verified HTTPS request to the readiness path. It never uses `-k`.
    func readinessRequest(_ hostname: Hostname, maximumTime: Int) -> ProcessRequest {
        let host = hostname.value
        let port = binding.httpsPort
        return ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: [
                "--noproxy", "*", "--silent", "--show-error", "--fail", "--max-time", String(maximumTime),
                "--cacert", layout.rootCertificateFile.path, "--resolve", "\(host):\(port):127.0.0.1",
                "https://\(host):\(port)\(SiteRoutePolicy.healthPath)",
            ],
            workingDirectory: layout.environment.root)
    }

    private func fpm(_ pool: Pool, mode: String) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: pool.runtime.fpmPath),
            arguments: ["-c", pool.layout.phpINIFile.path, "-y", pool.layout.fpmConfigurationFile.path, mode],
            workingDirectory: layout.environment.root, environment: layout.processEnvironment)
    }

    private func caddyRequest(_ arguments: [String], _ listeners: InheritedListeners?) -> ProcessRequest {
        ProcessRequest(
            executable: URL(fileURLWithPath: caddy.path), arguments: arguments,
            workingDirectory: layout.environment.root, environment: layout.processEnvironment, listeners: listeners)
    }
}

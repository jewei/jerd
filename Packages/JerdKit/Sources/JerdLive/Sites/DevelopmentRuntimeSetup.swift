import JerdFoundation
import JerdRuntimes
import JerdWeb

/// Loads the site configuration once and, on the first successful load, installs and registers
/// the bundled PHP and Caddy when they are missing. Sites and Advanced both read the
/// configuration through it, so the bundled runtimes are in place before either page shows it.
///
/// A failed load can be retried. A failed bundled setup does not fail the load: the sites stay
/// usable with the runtimes the user has, and Advanced shows the setup message.
package actor DevelopmentRuntimeSetup {
    package static let readyMessage =
        "PHP, Caddy, Composer, and the Laravel installer are installed and managed by Jerd."

    let registry: any SiteConfigurationLoading
    let sites: any SiteChangeApplying
    let source: any DevelopmentRuntimeSource
    /// The result of the bundled setup, or nil before the first successful load.
    package private(set) var message: String?
    private var isLoaded = false
    private var loading: Task<AppConfiguration, any Error>?

    package init(
        registry: any SiteConfigurationLoading, sites: any SiteChangeApplying, source: any DevelopmentRuntimeSource
    ) {
        self.registry = registry
        self.sites = sites
        self.source = source
    }

    package init(layout: DataLayout, bootstrap: BundledRuntimeBootstrap, web: WebDomain) {
        self.init(
            registry: web.registry, sites: web.transaction,
            source: BundledDevelopmentSource(bootstrap: bootstrap, layout: layout))
    }

    /// The saved configuration. The first call loads it and runs the bundled setup; concurrent
    /// calls wait for that one run.
    /// - Throws: When the file cannot be read. The file stays as it is, and a later call retries.
    package func loadConfiguration() async throws -> AppConfiguration {
        if isLoaded { return try await registry.snapshot() }
        if let loading { return try await loading.value }
        let task = Task { try await self.loadOnce() }
        loading = task
        defer { loading = nil }
        return try await task.value
    }

    private func loadOnce() async throws -> AppConfiguration {
        let configuration = try await registry.load()
        message = await installBundledRuntimes(into: configuration)
        isLoaded = true
        return try await registry.snapshot()
    }

    private func installBundledRuntimes(into configuration: AppConfiguration) async -> String {
        do {
            guard try await source.isNeeded(for: configuration) else { return Self.readyMessage }
            let records = try await source.install()
            for change in records.changes(for: configuration) {
                guard case .committed = try await sites.apply(change, startIfStopped: false) else {
                    throw JerdError.unavailable(
                        "The bundled runtimes need an HTTPS approval. Start a site to continue.")
                }
            }
            return Self.readyMessage
        } catch {
            return "Bundled runtime setup failed: \(error.localizedDescription)"
        }
    }
}

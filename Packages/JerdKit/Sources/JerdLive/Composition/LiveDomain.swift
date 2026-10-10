import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdProcess
import JerdRuntimes
import JerdServiceKit
import JerdStorage
import JerdSystem
import JerdTunnels

/// The domain objects of one app run, shared by the live ports. Each saved file and each
/// process has exactly one owner here, so two ports never race on the same data.
package struct LiveDomain: Sendable {
    package let configuration: LiveConfiguration
    /// The one graceful supervisor of every data service and tunnel connector. It never sends
    /// `SIGKILL`. Only the web engine has its own forceful supervisor (see `WebDomain`).
    package let processes: ProcessSupervisor
    package let effects: ServiceEffects
    package let helper: any HelperControlling
    package let bootstrap: BundledRuntimeBootstrap
    /// The one fetcher of runtime downloads and catalogs. Every request names the app version.
    package let fetcher: URLSessionFetcher
    /// The one installer of `runtime-updates/`: Runtimes updates and on-demand database engines
    /// share it, so only one installation runs at a time.
    package let runtimeInstaller: RuntimeInstaller
    /// The pinned runtimes that the app does not embed, from the catalog in the bundle.
    package let onDemandRuntimes: OnDemandRuntimes
    package let web: WebDomain
    package let developmentRuntimes: DevelopmentRuntimeSetup
    package let databases: DatabaseManager
    package let mail: MailManager
    package let storage: StorageManager
    package let connector: CloudflaredConnector
    package let tunnels: TunnelSupervisor

    package init(
        configuration: LiveConfiguration, helper: any HelperControlling = HelperClient(),
        processes: ProcessSupervisor = ProcessSupervisor(ceiling: .graceful), fetcher: URLSessionFetcher? = nil
    ) {
        let layout = configuration.layout
        self.configuration = configuration
        self.processes = processes
        self.helper = helper
        effects = ServiceEffects(processes: processes)
        bootstrap = BundledRuntimeBootstrap(resources: configuration.payloads, layout: layout)
        // Tests pass a fetcher with a local file server; the app uses HTTPS with its version.
        self.fetcher =
            fetcher ?? URLSessionFetcher(userAgent: URLSessionFetcher.userAgent(appVersion: configuration.appVersion))
        runtimeInstaller = RuntimeInstaller(
            directory: layout.runtimes.managedRuntimesDirectory, fetcher: self.fetcher,
            minimumMacOS: configuration.minimumMacOS)
        onDemandRuntimes = OnDemandRuntimes(resources: configuration.payloads)
        web = WebDomain(layout: layout, helper: helper, publicHosts: LiveTunnelHostSource(layout: layout.tunnels))
        developmentRuntimes = DevelopmentRuntimeSetup(layout: layout, bootstrap: bootstrap, web: web)
        databases = DatabaseManager(layout: layout.databases, effects: effects)
        mail = MailManager(layout: layout, effects: effects)
        storage = StorageManager(layout: layout, effects: effects)
        connector = CloudflaredConnector(
            layout: layout.tunnels, processes: processes,
            sites: LiveTunnelSiteResolver(
                registry: web.registry, environment: web.coordinator, layout: layout.environment))
        tunnels = TunnelSupervisor(layout: layout.tunnels, connector: connector)
    }

    package var layout: DataLayout { configuration.layout }
}

import Foundation
import JerdUI

/// An `AppState` on in-memory ports, with access to every port for tests and snapshots.
@MainActor
public final class AppFixture {
    public static let info = AppInfo(
        version: "0.1.0", build: "2", macOSVersion: "Version 26.0 (Build 25A354)",
        architecture: "Apple Silicon (arm64)", copyright: "Copyright © 2026 Jerd contributors")

    public let shell = InMemoryShell()
    public let iconImages = BundleIconImages()
    public let updater: InMemoryUpdater
    public let runtimes: InMemoryRuntimeInventory
    public let advanced: InMemoryAdvancedPorts
    public let panels: InMemoryFilePanels
    public let sites: InMemorySitesPort
    public let tunnels: InMemoryTunnelsPort
    public let features: [InMemoryFeature]
    public let services: InMemoryServicePorts
    /// The appearance defaults, in memory only: a fixture writes nothing to disk.
    public let defaults: UserDefaults
    public let state: AppState
    /// A name for the fixture's defaults, for messages. Nothing is stored under it.
    public let suiteName: String

    /// - Parameters:
    ///   - suiteName: A name for the fixture's in-memory defaults.
    ///   - sleeper: The poller clock; by default the poller never ticks.
    public init(
        suiteName: String = "dev.jerd.fixtures.\(UUID().uuidString)",
        runtimes: InMemoryRuntimeInventory = InMemoryRuntimeInventory(inventory: SampleData.inventory),
        advanced: InMemoryAdvancedPorts = InMemoryAdvancedPorts(registrations: SampleData.registrations),
        features: [InMemoryFeature] = SampleFeatures.all(.populated),
        services: InMemoryServicePorts = InMemoryServicePorts(.populated), updater: InMemoryUpdater = InMemoryUpdater(),
        panels: InMemoryFilePanels = InMemoryFilePanels(), sites: InMemorySitesPort = InMemorySitesPort(),
        tunnels: InMemoryTunnelsPort = InMemoryTunnelsPort(), sleeper: any Sleeping = IdleSleeper(),
        prepareDefaults: (UserDefaults) -> Void = { _ in }
    ) {
        self.suiteName = suiteName
        // InMemoryDefaults fails only when Foundation refuses a nil suite, which it never does.
        let defaults: UserDefaults = InMemoryDefaults(suiteName: suiteName) ?? UserDefaults()
        prepareDefaults(defaults)
        self.defaults = defaults
        self.runtimes = runtimes
        self.advanced = advanced
        self.features = features
        self.services = services
        self.updater = updater
        self.panels = panels
        self.sites = sites
        self.tunnels = tunnels
        let dependencies = AppDependencies(
            info: Self.info, defaults: defaults, presence: shell, iconImages: iconImages, updater: updater,
            runtimes: runtimes, recovery: advanced, executables: advanced, httpsRecovery: advanced, windows: shell,
            pasteboard: shell, workspace: shell, filePanels: panels, sleeper: sleeper,
            services: services.ports, sites: sites, tunnels: tunnels)
        state = AppState(dependencies: dependencies, features: features)
    }

    /// Removes every default that the fixture wrote. Nothing is on disk, so this only resets.
    public func removeDefaults() {
        (defaults as? InMemoryDefaults)?.removeAll()
    }
}

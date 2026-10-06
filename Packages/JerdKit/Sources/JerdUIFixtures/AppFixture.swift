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
    public let features: [InMemoryFeature]
    public let services: InMemoryServicePorts
    public let defaults: UserDefaults
    public let state: AppState
    private let suiteName: String

    /// - Parameters:
    ///   - suiteName: A private defaults domain. `removeDefaults()` deletes it.
    ///   - sleeper: The poller clock; by default the poller never ticks.
    public init(
        suiteName: String = "dev.jerd.fixtures.\(UUID().uuidString)",
        runtimes: InMemoryRuntimeInventory = InMemoryRuntimeInventory(inventory: SampleData.inventory),
        advanced: InMemoryAdvancedPorts = InMemoryAdvancedPorts(registrations: SampleData.registrations),
        features: [InMemoryFeature] = SampleFeatures.all(.populated),
        services: InMemoryServicePorts = InMemoryServicePorts(.populated), updater: InMemoryUpdater = InMemoryUpdater(),
        panels: InMemoryFilePanels = InMemoryFilePanels(), sleeper: any Sleeping = IdleSleeper(),
        prepareDefaults: (UserDefaults) -> Void = { _ in }
    ) {
        self.suiteName = suiteName
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        prepareDefaults(defaults)
        self.defaults = defaults
        self.runtimes = runtimes
        self.advanced = advanced
        self.features = features
        self.services = services
        self.updater = updater
        self.panels = panels
        let dependencies = AppDependencies(
            info: Self.info, defaults: defaults, presence: shell, iconImages: iconImages, updater: updater,
            runtimes: runtimes, recovery: advanced, executables: advanced, httpsRecovery: advanced, windows: shell,
            pasteboard: shell, workspace: shell, filePanels: panels, sleeper: sleeper,
            services: services.ports)
        state = AppState(dependencies: dependencies, features: features)
    }

    /// Deletes the private defaults domain.
    public func removeDefaults() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

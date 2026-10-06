import Foundation
import JerdManifest
import JerdRuntimes
import JerdUI

/// A named state of the whole window, for snapshots and previews.
public enum FixtureScenario: String, CaseIterable, Sendable {
    case dashboardEmpty = "dashboard-empty"
    case dashboard
    case dashboardBusy = "dashboard-busy"
    case dashboardLong = "dashboard-long"
    case quitting
    case appearance
    case appearanceHidden = "appearance-hidden"
    case runtimes
    case runtimesChecked = "runtimes-checked"
    case advancedEmpty = "advanced-empty"
    case advanced
    case about
    case aboutUpdateError = "about-update-error"
    case sitesEmpty = "sites-empty"
    case sitesRunning = "sites-running"
    case sitesStopped = "sites-stopped"
    case sitesDisabled = "sites-disabled"
    case sitesBusy = "sites-busy"
    case sitesFailed = "sites-failed"
    case sitesSetupRequired = "sites-setup-required"
    case sitesRecovery = "sites-recovery"
    case sitesLoadFailed = "sites-load-failed"
    case sitesLong = "sites-long"
    case tunnelConnected = "tunnel-connected"
    case tunnelStopped = "tunnel-stopped"
    case tunnelFailed = "tunnel-failed"

    /// Long pages also render at a tall size, so every section can be reviewed.
    public var showsFullPage: Bool {
        switch self {
        case .runtimesChecked, .advanced, .about, .appearance, .sitesRunning, .tunnelConnected: true
        default: false
        }
    }

    /// Builds the fixture and the navigation of the scenario. Run `prepare` before rendering.
    @MainActor
    public func makeFixture() -> AppFixture {
        let fixture = AppFixture(
            suiteName: "dev.jerd.fixtures.snapshot", runtimes: runtimeInventory(), advanced: advancedPorts(),
            features: SampleFeatures.all(variant), services: InMemoryServicePorts(variant), updater: updater(),
            sites: sitesPort(), tunnels: tunnelsPort()
        ) { defaults in
            if self == .appearanceHidden {
                AppearanceDefaults(defaults).setShowMenuBar(false)
                AppearanceDefaults(defaults).setShowDock(false)
                AppearanceDefaults(defaults).setIcon(.elephant)
            }
        }
        fixture.state.navigation.show(destination)
        return fixture
    }

    private var variant: SampleFeatures.Variant {
        switch self {
        case .dashboardEmpty, .advancedEmpty: .empty
        case .dashboardBusy: .busy
        case .dashboardLong: .long
        default: .populated
        }
    }

    private var destination: Destination {
        switch self {
        case .dashboardEmpty, .dashboard, .dashboardBusy, .dashboardLong, .quitting: .dashboard(.overview)
        case .appearance, .appearanceHidden: .dashboard(.appearance)
        case .runtimes, .runtimesChecked: .dashboard(.runtimes)
        case .advancedEmpty, .advanced: .dashboard(.advanced)
        case .about, .aboutUpdateError: .dashboard(.about)
        default: sitesDestination
        }
    }

    @MainActor
    private func runtimeInventory() -> InMemoryRuntimeInventory {
        let empty = self == .dashboardEmpty
        let report = RuntimeInstallProgress("Downloading Mailpit 1.28.0… 12.4 MB of 19.8 MB", 0.63)
        return InMemoryRuntimeInventory(
            inventory: empty ? RuntimeInventorySnapshot() : SampleData.inventory, results: SampleData.checks,
            installBehavior: self == .runtimesChecked ? .suspend(report) : .succeed)
    }

    @MainActor
    private func advancedPorts() -> InMemoryAdvancedPorts {
        guard self == .advanced else { return InMemoryAdvancedPorts() }
        return InMemoryAdvancedPorts(
            findings: SampleData.findings, backups: SampleData.backups, registrations: SampleData.registrations,
            httpsStatus: SampleData.httpsRecovery)
    }

    @MainActor
    private func updater() -> InMemoryUpdater {
        InMemoryUpdater(
            initialState: AppUpdaterState(canCheck: true, automaticallyChecks: true, lastCheck: SampleData.now))
    }
}

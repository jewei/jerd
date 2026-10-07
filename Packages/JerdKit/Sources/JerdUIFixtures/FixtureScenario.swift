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
    /// An app without the database runtimes: the page offers the pinned engines.
    case runtimesOnDemand = "runtimes-on-demand"
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
    case sitesApproving = "sites-approving"
    case tunnelConnected = "tunnel-connected"
    case tunnelStopped = "tunnel-stopped"
    case tunnelFailed = "tunnel-failed"
    case tunnelSettingsIssue = "tunnel-settings-issue"
    case tunnelSiteRemoved = "tunnel-site-removed"

    /// Long pages also render at a tall size, so every section can be reviewed.
    public var showsFullPage: Bool {
        switch self {
        case .runtimesChecked, .runtimesOnDemand, .advanced, .about, .appearance, .sitesRunning, .tunnelConnected: true
        default: false
        }
    }

    /// Builds the fixture and the navigation of the scenario. Run `prepare` before rendering.
    @MainActor
    public func makeFixture() -> AppFixture {
        let fixture = AppFixture(
            runtimes: runtimeInventory(), advanced: advancedPorts(),
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

    package var destination: Destination {
        switch self {
        case .dashboardEmpty, .dashboard, .dashboardBusy, .dashboardLong, .quitting: .dashboard(.overview)
        case .appearance, .appearanceHidden: .dashboard(.appearance)
        case .runtimes, .runtimesChecked, .runtimesOnDemand: .dashboard(.runtimes)
        case .advancedEmpty, .advanced: .dashboard(.advanced)
        case .about, .aboutUpdateError: .dashboard(.about)
        default: sitesDestination
        }
    }

    @MainActor
    private func runtimeInventory() -> InMemoryRuntimeInventory {
        let empty = self == .dashboardEmpty
        let report = RuntimeInstallProgress("Downloading Mailpit 1.28.0… 12.4 MB of 19.8 MB", 0.63)
        let inventory =
            empty
            ? RuntimeInventorySnapshot()
            : self == .runtimesOnDemand ? SampleData.onDemandInventory : SampleData.inventory
        return InMemoryRuntimeInventory(
            inventory: inventory, results: SampleData.checks,
            installBehavior: self == .runtimesChecked ? .suspend(report) : .succeed)
    }

    @MainActor
    private func advancedPorts() -> InMemoryAdvancedPorts {
        switch self {
        case .dashboardEmpty, .advancedEmpty: return InMemoryAdvancedPorts()
        case .advanced: break
        default: return InMemoryAdvancedPorts(registrations: SampleData.registrations)
        }
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

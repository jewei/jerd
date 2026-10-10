import Foundation
import JerdSnapshotSupport
import JerdTunnels
import JerdUI
import JerdWeb

extension FixtureScenario {
    /// The sites, environment, and HTTPS setup of the scenario.
    @MainActor
    func sitesPort() -> InMemorySitesPort {
        let served: Set<UUID> = [SampleData.studioID, SampleData.northwindID]
        switch self {
        case .dashboardEmpty, .sitesEmpty:
            return InMemorySitesPort(configuration: AppConfiguration())
        case .dashboardLong, .sitesLong:
            let ids = Set(SampleData.longSiteConfiguration.sites.prefix(12).map(\.id))
            let setup = HTTPSSetupStatus(
                hostnames: SampleData.longSiteConfiguration.sites.map(\.hostname),
                installationID: SampleData.installationID, certificateSHA256: SampleData.caFingerprint,
                hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS)
            return InMemorySitesPort(
                configuration: SampleData.longSiteConfiguration, environment: running(ids), setup: setup)
        case .sitesStopped, .sitesBusy, .dashboardBusy, .sitesDisabled:
            return InMemorySitesPort()
        case .sitesFailed:
            return InMemorySitesPort(
                environment: EnvironmentSnapshot(
                    state: .failed("PHP-FPM did not answer its private ping within 10 seconds. Check the web logs."),
                    siteIDs: []))
        case .sitesApproving:
            return InMemorySitesPort(setup: HTTPSSetupStatus())
        case .sitesSetupRequired:
            return InMemorySitesPort(
                environment: EnvironmentSnapshot(state: .setupRequired, siteIDs: []), setup: HTTPSSetupStatus())
        case .sitesLoadFailed:
            return InMemorySitesPort(
                loadFailure: "The JSON is not valid at line 14.")
        case .sitesRecovery:
            var setup = SampleData.approvedSetup
            setup.hasPendingRecovery = true
            return InMemorySitesPort(setup: setup)
        case .sitesHelperStale, .sitesHelperNotAllowed:
            return InMemorySitesPort(
                setupFailure: self == .sitesHelperStale
                    ? SampleData.staleHelperFailure : SampleData.helperNotAllowedFailure)
        default:
            return InMemorySitesPort(environment: running(served))
        }
    }

    /// The tunnels of the scenario.
    @MainActor
    func tunnelsPort() -> InMemoryTunnelsPort {
        switch self {
        case .dashboardEmpty, .sitesEmpty:
            return InMemoryTunnelsPort(configuration: TunnelConfiguration())
        case .tunnelFailed:
            var configuration = SampleData.tunnelConfiguration
            configuration.tunnels[1].hostname = "203.0.113.10"
            return InMemoryTunnelsPort(
                configuration: configuration,
                states: [
                    SampleData.previewTunnelID: .connected,
                    SampleData.docsTunnelID: .failed(
                        "Cloudflare rejected the tunnel token. Edit this tunnel to replace its token."),
                ])
        case .sitesStopped, .tunnelStopped, .sitesApproving:
            return InMemoryTunnelsPort(states: [:])
        case .tunnelSettingsIssue:
            var configuration = SampleData.tunnelConfiguration
            configuration.tunnels[1].hostname = "203.0.113.10"
            return InMemoryTunnelsPort(configuration: configuration, states: [:])
        case .tunnelSiteRemoved:
            var configuration = SampleData.tunnelConfiguration
            configuration.tunnels[1].siteID = SampleData.removedSiteID
            configuration.tunnels[1].originURL = nil
            return InMemoryTunnelsPort(configuration: configuration, states: [:])
        default:
            return InMemoryTunnelsPort(states: servesStudio ? SampleData.tunnelStates : [:])
        }
    }

    /// True when `sitesPort()` runs Studio, so Studio preview can be connected. A Jerd route to a
    /// site that does not run is stopped, as the app stops it.
    private var servesStudio: Bool {
        switch self {
        case .dashboardEmpty, .sitesEmpty, .dashboardLong, .sitesLong, .sitesStopped, .sitesBusy, .dashboardBusy,
            .sitesDisabled, .sitesFailed, .sitesApproving, .sitesSetupRequired, .sitesLoadFailed, .sitesRecovery,
            .sitesHelperStale, .sitesHelperNotAllowed:
            false
        default:
            true
        }
    }

    /// The window appearances of a scenario. At least one scenario of each page, and the Sites
    /// and tunnel pages with tinted banners and badges, also render with Increase Contrast.
    package var snapshotAppearances: [SnapshotAppearance] {
        switch self {
        case .dashboard, .appearance, .runtimesChecked, .runtimesOnDemand, .advanced, .about, .sitesEmpty,
            .sitesRunning, .sitesDisabled, .sitesSetupRequired, .sitesRecovery, .sitesHelperStale,
            .sitesHelperNotAllowed,
            .tunnelFailed, .tunnelConnected:
            SnapshotAppearance.allCases
        default: SnapshotAppearance.standard
        }
    }

    /// The page that a Sites scenario shows.
    var sitesDestination: Destination {
        switch self {
        case .tunnelConnected: .item(.tunnel(SampleData.previewTunnelID))
        case .tunnelStopped, .tunnelFailed, .tunnelSettingsIssue, .tunnelSiteRemoved:
            .item(.tunnel(SampleData.docsTunnelID))
        case .sitesDisabled: .item(.site(SampleData.legacyID))
        default: .section(.sites)
        }
    }

    /// Starts the work that a busy scenario shows.
    @MainActor
    func prepareSites(_ fixture: AppFixture) async {
        switch self {
        case .sitesBusy, .dashboardBusy:
            await fixture.sites.configure { $0.suspendsChanges = true }
            fixture.state.sites.startAll()
        case .sitesApproving:
            await fixture.sites.configure { $0.approvalGate = FixtureGate() }
            let sites = fixture.state.sites
            await sites.startAll()?.value
            if let approval = sites.sheet?.approval {
                sites.approve(approval)
                sites.cancelApproval()
            }
        default:
            break
        }
    }

    @MainActor
    func isSitesReady(_ fixture: AppFixture) -> Bool {
        switch self {
        case .sitesBusy, .dashboardBusy: fixture.state.sites.operation.isWorking
        case .sitesApproving: fixture.state.sites.runningApprovalID != nil
        default: true
        }
    }

    private func running(_ ids: Set<UUID>) -> EnvironmentSnapshot {
        EnvironmentSnapshot(state: .running, siteIDs: ids)
    }
}

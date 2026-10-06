import Foundation
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
                hostnames: SampleData.longSiteConfiguration.sites.map(\.hostname), hostsConfigured: true,
                trustConfigured: true, trustPolicy: .serverTLS)
            return InMemorySitesPort(
                configuration: SampleData.longSiteConfiguration, environment: running(ids), setup: setup)
        case .sitesStopped, .sitesBusy, .dashboardBusy, .sitesDisabled:
            return InMemorySitesPort()
        case .sitesFailed:
            return InMemorySitesPort(
                environment: EnvironmentSnapshot(
                    state: .failed("PHP-FPM did not answer its private ping within 10 seconds. Check the web logs."),
                    siteIDs: []))
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
                    SampleData.docsTunnelID: .failed(
                        "Cloudflare rejected the tunnel token. Edit this tunnel to replace its token.")
                ])
        case .sitesStopped, .tunnelStopped:
            return InMemoryTunnelsPort(configuration: stoppedTunnels)
        default:
            return InMemoryTunnelsPort()
        }
    }

    /// The page that a Sites scenario shows.
    var sitesDestination: Destination {
        switch self {
        case .tunnelConnected: .item(.tunnel(SampleData.previewTunnelID))
        case .tunnelStopped, .tunnelFailed: .item(.tunnel(SampleData.docsTunnelID))
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
        default:
            break
        }
    }

    @MainActor
    func isSitesReady(_ fixture: AppFixture) -> Bool {
        switch self {
        case .sitesBusy, .dashboardBusy: fixture.state.sites.operation.isWorking
        default: true
        }
    }

    private func running(_ ids: Set<UUID>) -> EnvironmentSnapshot {
        EnvironmentSnapshot(state: .running, siteIDs: ids)
    }

    /// The sample tunnels without "Connect when Jerd opens", so none connects at launch.
    private var stoppedTunnels: TunnelConfiguration {
        var configuration = SampleData.tunnelConfiguration
        configuration.tunnels = configuration.tunnels.map { tunnel in
            var stopped = tunnel
            stopped.startOnLaunch = false
            return stopped
        }
        return configuration
    }
}

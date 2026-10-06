import Foundation
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

@Suite("Sites feature", .timeLimit(.minutes(1)))
@MainActor
struct SitesFeatureTests {
    @Test("The card shows the count of running sites and tunnels, and Stop All Sites")
    func runningCard() async {
        let running = EnvironmentSnapshot(state: .running, siteIDs: [SampleData.studioID, SampleData.northwindID])
        let harness = await SitesHarness.launched(sites: InMemorySitesPort(environment: running))
        let summary = harness.model.summary
        #expect(summary.status.label == "2 running")
        #expect(summary.summary == "3 registered · 2 enabled · 1/2 tunnels connected")
        #expect(summary.actions.map(\.title) == ["Stop All Sites"])
    }

    @Test("Without sites the card offers Add Site… as the next step, which opens the editor in Sites")
    func emptyCard() async {
        let harness = await SitesHarness.launched(
            sites: InMemorySitesPort(configuration: AppConfiguration()),
            tunnels: InMemoryTunnelsPort(configuration: .init()))
        let summary = harness.model.summary
        #expect(summary.status.label == "No sites")
        #expect(summary.actions.map(\.title) == ["Add Site…"])
        #expect(summary.actions.first?.isPrimary == true)
        summary.actions.first?.perform()
        #expect(harness.recorder.shown == [.section(.sites)])
        #expect(harness.model.sheet?.editor?.isNew == true)
    }

    @Test("The menu lists the state, each enabled site, the run command, and the tunnels")
    func menu() async {
        let harness = await SitesHarness.launched()
        let titles = harness.model.menuItems.compactMap(\.title)
        #expect(titles == ["Stopped", "Open Studio", "Open Northwind Shop", "Start All Sites", "Tunnels"])
        guard case .submenu(_, let tunnels) = harness.model.menuItems.last?.kind,
            case .submenu(_, let preview) = tunnels.first?.kind
        else {
            Issue.record("No tunnel submenu")
            return
        }
        #expect(preview.compactMap(\.title) == ["Connected", "Open in Browser", "Manage Tunnel…", "Stop Connector"])
        if case .action(let manage) = preview[2].kind { manage.perform() }
        #expect(harness.recorder.opened == [.item(.tunnel(SampleData.previewTunnelID))])
    }

    @Test("Shutdown: pending site work stops first, PHP-FPM and Caddy stop last")
    func shutdownParticipants() async {
        let harness = await SitesHarness.launched()
        let phases = harness.model.shutdownParticipants.map(\.shutdownPhase)
        #expect(phases == [.siteWork, .tunnels, .webEnvironment])
        #expect(await harness.model.shutdown())
        #expect(await harness.sites.calls.last == "stop environment")
        harness.model.resumeAfterCancelledQuit()
        #expect(!harness.model.isShuttingDown)
    }

    @Test("A failed stop of PHP-FPM and Caddy keeps Jerd open and shows on the page")
    func shutdownFailure() async {
        let port = InMemorySitesPort()
        let harness = await SitesHarness.launched(sites: port)
        await port.configure { $0.failure = "Caddy did not stop." }
        #expect(await !harness.model.shutdown())
        #expect(harness.model.operation.failureMessage == "Caddy did not stop.")
    }

    @Test("The site work stage ends a stoppable change and disables every action")
    func siteWorkStage() async {
        let port = InMemorySitesPort()
        await port.configure { $0.suspendsChanges = true }
        let harness = await SitesHarness.launched(sites: port)
        _ = harness.model.startAll()
        let stage = harness.model.siteWorkStage
        #expect(stage.shutdownMessage == "Cancelling preparation…")
        #expect(await stage.shutdown())
        #expect(harness.model.isBusy)
        #expect(!harness.model.canChange)
        #expect(harness.model.startAll() == nil)
        #expect(await port.calls.contains("request stop"))
        stage.resumeAfterCancelledQuit()
        #expect(harness.model.canChange)
    }

    @Test("The app state builds the Sites feature from its ports and lets it navigate")
    func appStateWiring() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        #expect(fixture.state.feature(for: .sites) === fixture.state.sites)
        await fixture.state.launch()
        fixture.state.sites.tunnels.menuItems.first.map { item in
            if case .submenu(_, let tunnels) = item.kind, case .submenu(_, let first) = tunnels.first?.kind,
                case .action(let manage) = first[2].kind
            {
                manage.perform()
            }
        }
        #expect(fixture.state.navigation.selection(in: .sites) == .tunnel(SampleData.previewTunnelID))
        #expect(fixture.shell.windowRequests == 1)
    }
}

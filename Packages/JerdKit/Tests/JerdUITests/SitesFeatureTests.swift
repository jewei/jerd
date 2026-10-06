import Foundation
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

@Suite("Sites feature", .timeLimit(.minutes(1)))
@MainActor
struct SitesFeatureTests {
    @Test("The card shows the count of running sites and tunnels, Stop All, and Open Site")
    func runningCard() async {
        let running = EnvironmentSnapshot(state: .running, siteIDs: [SampleData.studioID, SampleData.northwindID])
        let harness = await SitesHarness.launched(sites: InMemorySitesPort(environment: running))
        let summary = harness.model.summary
        #expect(summary.status.label == "2 running")
        #expect(summary.summary == "3 registered · 2 enabled · 1/2 tunnels connected")
        #expect(summary.actions.map(\.title) == ["Stop All", "Open Site"])
        #expect(summary.actions.map(\.spokenTitle) == ["Stop All Sites", "Open Studio"])
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

    @Test("Shutdown: tunnels stop, then PHP-FPM and Caddy last")
    func shutdownParticipants() async {
        let harness = await SitesHarness.launched()
        let phases = harness.model.shutdownParticipants.map(\.shutdownPhase)
        #expect(phases == [.tunnels, .webEnvironment])
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

    @Test("The quit closes the shared lock, stops a stoppable change, and no new work starts")
    func quitStopsSiteWork() async {
        let port = InMemorySitesPort()
        await port.configure { $0.suspendsChanges = true }
        let harness = await SitesHarness.launched(sites: port)
        _ = harness.model.startAll()
        #expect(harness.lock.work?.canCancel == true)
        #expect(await harness.lock.shutdown())
        #expect(!harness.model.canChange)
        #expect(harness.model.startAll() == nil)
        #expect(await port.calls.contains("request stop"))
        #expect(harness.model.operation == .idle)
        harness.lock.resumeAfterCancelledQuit()
        #expect(harness.model.canChange)
    }

    @Test("Other work that holds the shared lock blocks site changes; File › New follows the rule")
    func sharedLock() async {
        let harness = await SitesHarness.launched()
        #expect(harness.model.newItemAction?.title == "New Site…")
        #expect(harness.model.newItemAction?.isEnabled == true)
        let other = harness.lock.run("Removing the selected backup…") {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!harness.model.canChange)
        #expect(harness.model.newItemAction?.isEnabled == false)
        #expect(harness.model.startAll() == nil)
        await other?.value
        #expect(harness.model.canChange)
        harness.model.newItemAction?.perform()
        #expect(harness.model.sheet?.editor?.isNew == true)
    }

    @Test("While site work runs, Open <site> and Retry Load are off, and the page leaves Stop to the banner")
    func busyGuardsOutsideThePage() async {
        let port = InMemorySitesPort(environment: EnvironmentSnapshot(state: .running, siteIDs: [SampleData.studioID]))
        let harness = await SitesHarness.launched(sites: port)
        let open = { harness.model.menuItems.compactMap(\.action).first { $0.id.hasPrefix("sites.open.") } }
        #expect(open()?.isEnabled == true)
        #expect(harness.model.showsStopAllOnPage)
        await port.configure { $0.suspendsChanges = true }
        let start = harness.model.start(SampleData.northwind)
        #expect(open()?.isEnabled == false)
        #expect(!harness.model.canRetryLoad)
        #expect(harness.model.bannerActivity?.stop != nil)
        #expect(!harness.model.showsStopAllOnPage)
        await port.configure { $0.suspendsChanges = false }
        await harness.model.stopAll()?.value
        await start?.value
    }

    @Test("Sites polls the environment and the tunnels at their own intervals")
    func pollingTasks() async {
        let harness = await SitesHarness.launched()
        #expect(harness.model.pollingTasks.map(\.policy) == [.environment, .tunnels])
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

    @Test("The app state gives the Sites models its shell at init, so a failed system setup reaches the window alert")
    func appStateShellAlert() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        await fixture.sites.configure { $0.failure = "The helper could not be registered." }
        fixture.state.sites.confirmation = .reconnectHelper
        await fixture.state.sites.confirm()?.value
        #expect(
            fixture.state.alert
                == AppAlert(title: "System Setup Did Not Finish", message: "The helper could not be registered."))
        fixture.state.sites.shell.show(.item(.site(SampleData.northwindID)))
        #expect(fixture.state.navigation.selection(in: .sites) == .site(SampleData.northwindID))
    }
}

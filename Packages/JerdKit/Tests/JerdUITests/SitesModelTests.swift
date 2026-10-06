import Foundation
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

@Suite("Sites model", .timeLimit(.minutes(1)))
@MainActor
struct SitesModelTests {
    private let running = EnvironmentSnapshot(state: .running, siteIDs: [SampleData.studioID])

    @Test("Launch reads the sites, the environment, the HTTPS setup, and the tunnels")
    func launch() async {
        let harness = await SitesHarness.launched(sites: InMemorySitesPort(environment: running))
        let model = harness.model
        #expect(model.isLoaded)
        #expect(model.sites == SampleData.siteConfiguration.sites)
        #expect(model.environment == running)
        #expect(model.setup == SampleData.approvedSetup)
        #expect(model.tunnels.isLoaded)
        #expect(model.operation == .idle)
    }

    @Test("A failed load keeps the file, shows why, and Retry Load reads it again")
    func loadFailure() async {
        let port = InMemorySitesPort(loadFailure: "The JSON is not valid.")
        let harness = await SitesHarness.launched(sites: port)
        #expect(!harness.model.isLoaded)
        #expect(
            harness.model.operation.failureMessage
                == "Site settings could not be loaded. The existing file was preserved. The JSON is not valid.")
        harness.model.beginAdd()
        #expect(harness.model.sheet == nil)
        #expect(harness.model.shownItem(for: nil) == nil)
        #expect(
            harness.model.shownItem(for: .tunnel(SampleData.previewTunnelID)) == .tunnel(SampleData.previewTunnelID))
        await port.configure { $0.loadFailure = nil }
        await harness.model.retryLoad()?.value
        #expect(harness.model.isLoaded)
        #expect(harness.model.shownItem(for: nil) == .site(SampleData.studioID))
        #expect(harness.model.operation == .idle)
    }

    @Test("Start All serves every enabled site")
    func startAll() async {
        let harness = await SitesHarness.launched()
        await harness.model.startAll()?.value
        #expect(harness.model.environment.siteIDs == [SampleData.studioID, SampleData.northwindID])
        #expect(await harness.sites.calls.contains("run 2"))
    }

    @Test("Start adds one site and Stop removes only that site")
    func startAndStopOne() async {
        let harness = await SitesHarness.launched(sites: InMemorySitesPort(environment: running))
        await harness.model.start(SampleData.northwind)?.value
        #expect(harness.model.environment.siteIDs == [SampleData.studioID, SampleData.northwindID])
        await harness.model.stop(SampleData.studio)?.value
        #expect(harness.model.environment.siteIDs == [SampleData.northwindID])
        await harness.model.stop(SampleData.northwind)?.value
        #expect(harness.model.environment.state == .stopped)
    }

    @Test(
        "Start refuses without enabled sites, a disabled site, or Caddy, before any work",
        arguments: [
            ("no-enabled", "Enable at least one registered site."),
            ("disabled", "The selected sites changed or are disabled. Select the sites again."),
            ("no-caddy", "Caddy is unavailable. Install Caddy in Runtimes, or select it in Advanced."),
        ])
    func startRules(rule: String, message: String) async {
        var configuration = SampleData.siteConfiguration
        switch rule {
        case "no-enabled": configuration.sites = [SampleData.legacy]
        case "no-caddy": configuration.caddy = nil
        default: break
        }
        let harness = await SitesHarness.launched(sites: InMemorySitesPort(configuration: configuration))
        if rule == "disabled" {
            await harness.model.start(SampleData.legacy)?.value
        } else {
            await harness.model.startAll()?.value
        }
        #expect(harness.model.operation.failureMessage == message)
        #expect(await !harness.sites.calls.contains { $0.hasPrefix("run") })
    }

    @Test("A start of unapproved hostnames opens the approval; Approve applies it and starts")
    func approvalFlow() async throws {
        let port = InMemorySitesPort(setup: HTTPSSetupStatus())
        let harness = await SitesHarness.launched(sites: port)
        #expect(!harness.model.isApproved(SampleData.studio))
        await harness.model.startAll()?.value
        let approval = try #require(harness.model.sheet?.approval)
        #expect(approval.hostnames == ["legacy-blog.test", "northwind.test", "studio.test"])
        #expect(approval.title == "Enable HTTPS for 3 sites?")
        #expect(harness.model.environment.siteIDs.isEmpty)
        await harness.model.approve(approval)?.value
        #expect(harness.model.sheet == nil)
        #expect(harness.model.environment.siteIDs.count == 2)
        #expect(harness.model.isApproved(SampleData.studio))
    }

    @Test("Cancel of a waiting approval discards it; a failed approval stays in the sheet")
    func approvalCancelAndFailure() async throws {
        let port = InMemorySitesPort(setup: HTTPSSetupStatus())
        let harness = await SitesHarness.launched(sites: port)
        await harness.model.startAll()?.value
        let approval = try #require(harness.model.sheet?.approval)
        await port.configure { $0.failure = "Allow Jerd in Login Items & Extensions, then retry." }
        await harness.model.approve(approval)?.value
        #expect(harness.model.sheet?.approval == approval)
        #expect(harness.model.approvalFailure == "Allow Jerd in Login Items & Extensions, then retry.")
        #expect(harness.model.operation == .idle)
        #expect(harness.recorder.alerts.isEmpty)
        harness.model.cancelApproval()
        #expect(harness.model.sheet == nil)
        for _ in 0..<1_000 where await !port.calls.contains("discard") { await Task.yield() }
        #expect(await port.calls.contains("discard"))
    }

    @Test("An approval that fails after its sheet closed uses the window alert")
    func approvalFailureAfterCancel() async throws {
        let port = InMemorySitesPort(setup: HTTPSSetupStatus())
        let harness = await SitesHarness.launched(sites: port)
        await harness.model.startAll()?.value
        let approval = try #require(harness.model.sheet?.approval)
        await port.configure { $0.failure = "The helper did not answer." }
        let task = harness.model.approve(approval)
        harness.model.cancelApproval()
        await task?.value
        #expect(
            harness.recorder.alerts == [
                AppAlert(title: "HTTPS Setup Did Not Finish", message: "The helper did not answer.")
            ])
        #expect(await !port.calls.contains("discard"))
    }

    @Test("Stop All during a start requests a stop, waits, then stops PHP-FPM and Caddy")
    func stopAllDuringStart() async {
        let port = InMemorySitesPort()
        await port.configure { $0.suspendsChanges = true }
        let harness = await SitesHarness.launched(sites: port)
        let start = harness.model.startAll()
        await waitUntil { harness.model.bannerActivity?.stop != nil }
        #expect(harness.model.bannerActivity?.message == "Checking PHP-FPM and HTTPS…")
        #expect(harness.model.bannerActivity?.stop?.title == "Stop All Sites")
        await port.configure { $0.suspendsChanges = false }
        await harness.model.stopAll()?.value
        await start?.value
        let calls = await port.calls
        #expect(calls.suffix(3) == ["run 2", "request stop", "stop environment"])
        #expect(harness.model.operation == .idle)
    }

    @Test("Actions are no-ops while an operation runs")
    func busyGuards() async {
        let port = InMemorySitesPort()
        await port.configure { $0.suspendsChanges = true }
        let harness = await SitesHarness.launched(sites: port)
        _ = harness.model.startAll()
        #expect(harness.model.isBusy)
        #expect(harness.model.start(SampleData.studio) == nil)
        #expect(harness.model.setEnabled(SampleData.studio, false) == nil)
        harness.model.beginAdd()
        #expect(harness.model.sheet == nil)
        await port.configure { $0.suspendsChanges = false }
        await harness.model.stopAll()?.value
    }

    @Test("Disable changes only the start flag")
    func setEnabled() async {
        let harness = await SitesHarness.launched()
        await harness.model.setEnabled(SampleData.studio, false)?.value
        #expect(harness.model.site(SampleData.studioID)?.isEnabled == false)
        #expect(harness.model.enabledSiteIDs == [SampleData.northwindID])
    }

    @Test("Remove asks first, then removes only the registration")
    func removeSite() async {
        let harness = await SitesHarness.launched()
        harness.model.requestRemoval(SampleData.northwind)
        #expect(harness.model.confirmation == .removeSite(SampleData.northwind))
        #expect(await !harness.sites.calls.contains { $0.hasPrefix("apply remove") })
        await harness.model.confirm()?.value
        #expect(harness.model.site(SampleData.northwindID) == nil)
        #expect(harness.model.confirmation == nil)
    }

    @Test("A failed system setup step uses the window alert, once")
    func systemStepFailure() async {
        let port = InMemorySitesPort()
        let harness = await SitesHarness.launched(sites: port)
        await port.configure { $0.failure = "The helper could not be registered." }
        harness.model.confirmation = .reconnectHelper
        await harness.model.confirm()?.value
        #expect(
            harness.recorder.alerts == [
                AppAlert(title: "System Setup Did Not Finish", message: "The helper could not be registered.")
            ])
        #expect(harness.model.operation == .idle)
    }

    @Test("Remove System Setup leaves the environment needing approval, and the page says so")
    func removeSystemSetup() async {
        let harness = await SitesHarness.launched()
        harness.model.confirmation = .removeSystemSetup
        await harness.model.confirm()?.value
        #expect(harness.model.environment.state == .setupRequired)
        #expect(harness.model.systemSetupState == .approvalRequired)
    }

    @Test("A pending HTTPS recovery blocks Start and links to Advanced")
    func recoveryBlocksStart() async {
        var setup = SampleData.approvedSetup
        setup.hasPendingRecovery = true
        let harness = await SitesHarness.launched(sites: InMemorySitesPort(setup: setup))
        #expect(harness.model.systemSetupState == .recoveryPending)
        #expect(harness.model.systemSetupState?.opensAdvanced == true)
        #expect(!harness.model.canStart)
        #expect(harness.model.canChange)
    }

    @Test("Copy writes the address and shows the window toast; links open and reveal")
    func links() async {
        let harness = await SitesHarness.launched()
        harness.model.copyAddress(SampleData.studio)
        #expect(harness.shell.pasteboard == ["https://studio.test"])
        #expect(harness.clipboard.feedback?.text == "Copied site URL")
        harness.model.openInBrowser(SampleData.studio)
        harness.model.revealProject(SampleData.studio)
        #expect(harness.shell.openedURLs.map(\.absoluteString) == ["https://studio.test"])
        #expect(harness.shell.revealedURLs.map(\.path) == [SampleData.studio.projectPath])
    }

    @Test("Open Logs without a log says so on the page")
    func missingLogs() async {
        let harness = await SitesHarness.launched()
        harness.model.openLogs()
        await waitUntil { harness.model.operation.failureMessage != nil }
        #expect(harness.model.operation.failureMessage == "The web environment log is not available yet.")
        harness.model.dismissFailure()
        #expect(harness.model.operation == .idle)
    }

    @Test("Refresh applies a new environment snapshot")
    func refresh() async {
        let port = InMemorySitesPort()
        let harness = await SitesHarness.launched(sites: port)
        await port.configure {
            $0.environmentValue = EnvironmentSnapshot(state: .running, siteIDs: [SampleData.studioID])
        }
        await harness.model.refresh()
        #expect(harness.model.environment.siteIDs == [SampleData.studioID])
    }
}

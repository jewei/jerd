import Foundation
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

/// Work that changes the Mac (HTTPS approval, Remove System Setup, Reconnect Helper, Remove
/// Registration) cannot stop at a next step. Stop All Sites stays off while it runs, and the
/// approval sheet never discards an approval that still runs.
@Suite("Sites unstoppable work", .timeLimit(.minutes(1)))
@MainActor
struct SitesUnstoppableWorkTests {
    private let running = EnvironmentSnapshot(state: .running, siteIDs: [SampleData.studioID])

    @Test("A running approval turns off Stop All Sites, and Cancel never discards it")
    func runningApprovalCannotStopOrDiscard() async throws {
        let port = InMemorySitesPort(setup: HTTPSSetupStatus())
        let harness = await SitesHarness.launched(sites: port)
        await harness.model.startAll()?.value
        let approval = try #require(harness.model.sheet?.approval)
        let gate = FixtureGate()
        await port.configure { $0.approvalGate = gate }
        let task = harness.model.approve(approval)
        #expect(harness.model.runningApprovalID == approval.id)
        #expect(!harness.model.canStopAll)
        #expect(harness.model.stopAll() == nil)
        #expect(harness.model.systemSetupState == .inProgress(SitesModel.approvalMessage))
        harness.model.cancelApproval()
        #expect(harness.model.sheet == nil)
        #expect(harness.model.systemSetupState == .inProgress(SitesModel.approvalMessage))
        await gate.open()
        await task?.value
        let calls = await port.calls
        #expect(!calls.contains("request stop"))
        #expect(!calls.contains("discard"))
        #expect(harness.model.runningApprovalID == nil)
        #expect(harness.model.systemSetupState == nil)
    }

    @Test(
        "Stop All Sites stays off while a system step or a removal runs",
        arguments: [SitesConfirmation.removeSystemSetup, .reconnectHelper, .removeSite(SampleData.northwind)])
    func systemStepsCannotStop(step: SitesConfirmation) async {
        let port = InMemorySitesPort(environment: running)
        let harness = await SitesHarness.launched(sites: port)
        await port.configure { $0.suspendsChanges = true }
        harness.model.confirmation = step
        let task = harness.model.confirm()
        #expect(harness.model.operation.isWorking)
        #expect(harness.model.showsStopAll)
        #expect(!harness.model.canStopAll)
        #expect(harness.model.stopAll() == nil)
        #expect(harness.model.bannerActivity?.stop == nil)
        let stopAll = harness.model.menuItems.compactMap(\.action).first { $0.id == "sites.stop-all" }
        #expect(stopAll?.isEnabled == false)
        #expect(harness.model.summary.actions.first?.isEnabled == false)
        await port.requestStop()
        await task?.value
        #expect(await port.calls.filter { $0 == "request stop" }.count == 1)
    }

    @Test("Stop All Sites still ends a start at its next step")
    func stoppableWorkStillStops() async {
        let port = InMemorySitesPort()
        await port.configure { $0.suspendsChanges = true }
        let harness = await SitesHarness.launched(sites: port)
        let start = harness.model.startAll()
        #expect(harness.model.canStopAll)
        await port.configure { $0.suspendsChanges = false }
        await harness.model.stopAll()?.value
        await start?.value
        #expect(await port.calls.contains("request stop"))
        #expect(harness.model.operation == .idle)
    }
}

extension MenuBarItem {
    /// The action of an action item, for tests.
    var action: FeatureAction? {
        if case .action(let action) = kind { return action }
        return nil
    }
}

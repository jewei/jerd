import Foundation
import JerdTunnels
import JerdUIFixtures
import Testing

@testable import JerdUI

/// The tunnel page: the next step, the titled banners, a stop failure that an edit cannot
/// hide, and the page that a failed quit opens.
@Suite("Tunnel page rules", .timeLimit(.minutes(1)))
@MainActor
struct TunnelPageRulesTests {
    @Test("Edit Tunnel… is the next step of a failed tunnel or one whose settings need an edit")
    func nextStep() async {
        var configuration = SampleData.tunnelConfiguration
        configuration.tunnels[1].hostname = "203.0.113.10"
        let port = InMemoryTunnelsPort(
            configuration: configuration,
            states: [SampleData.previewTunnelID: .connected, SampleData.docsTunnelID: .failed("x")])
        let harness = await SitesHarness.launched(tunnels: port)
        let model = harness.model.tunnels
        #expect(model.nextStep(for: SampleData.previewTunnelID) == .open)
        #expect(model.nextStep(for: SampleData.docsTunnelID) == .edit)
        await port.configure { $0.states[SampleData.docsTunnelID] = .stopped }
        await model.refresh()
        #expect(model.nextStep(for: SampleData.docsTunnelID) == .edit)
        await port.configure { $0.configurationValue = SampleData.tunnelConfiguration }
        await model.refresh()
        #expect(model.nextStep(for: SampleData.docsTunnelID) == .connect)
        #expect(TunnelNextStep.edit.title == "Edit Tunnel…")
    }

    @Test("A failed connector's banner has a title and offers Edit Tunnel… once")
    func failureBanner() async {
        let rejected = "Cloudflare rejected the tunnel token. Edit this tunnel to replace its token."
        let port = InMemoryTunnelsPort(states: [SampleData.docsTunnelID: .failed(rejected)])
        await port.configure {
            $0.startupFailures = [TunnelStartupFailure(id: SampleData.docsTunnelID, name: "Docs", message: "No token.")]
        }
        let harness = await SitesHarness.launched(tunnels: port)
        await port.configure { $0.states[SampleData.docsTunnelID] = .failed(rejected) }
        await harness.model.tunnels.refresh()
        #expect(
            harness.model.tunnels.banners(for: SampleData.docsTunnelID) == [
                TunnelBanner(title: "The connector stopped", message: rejected, offersEdit: true),
                TunnelBanner(
                    title: "The tunnel did not connect when Jerd opened", message: "No token.", offersEdit: false),
            ])
    }

    @Test("A banner that offers Edit Tunnel… takes it from the header, so the page shows it once")
    func bannerTakesEditFromHeader() async {
        let port = InMemoryTunnelsPort(states: [SampleData.docsTunnelID: .failed("Cloudflare rejected the token.")])
        let harness = await SitesHarness.launched(tunnels: port)
        let model = harness.model.tunnels
        #expect(model.nextStep(for: SampleData.docsTunnelID) == .edit)
        #expect(model.bannerOffersEdit(for: SampleData.docsTunnelID))
        #expect(!model.bannerOffersEdit(for: SampleData.previewTunnelID))

        var configuration = SampleData.tunnelConfiguration
        configuration.tunnels[1].hostname = "203.0.113.10"
        let settings = InMemoryTunnelsPort(configuration: configuration)
        let issue = await SitesHarness.launched(tunnels: settings)
        #expect(issue.model.tunnels.bannerOffersEdit(for: SampleData.docsTunnelID))
    }

    @Test("A settings issue banner owns Edit Tunnel…, so the failure banner does not repeat it")
    func settingsIssueOwnsEdit() async {
        var configuration = SampleData.tunnelConfiguration
        configuration.tunnels[1].hostname = "203.0.113.10"
        let port = InMemoryTunnelsPort(configuration: configuration, states: [SampleData.docsTunnelID: .failed("x")])
        let harness = await SitesHarness.launched(tunnels: port)
        #expect(harness.model.tunnels.banners(for: SampleData.docsTunnelID).map(\.offersEdit) == [false])
    }

    @Test("A stop failure while an edit runs stays on the tunnel page")
    func stopFailureDuringEdit() async throws {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        let model = harness.model.tunnels
        let gate = FixtureGate()
        await port.configure {
            $0.saveGate = gate
            $0.stopFails = true
        }
        model.beginEdit(SampleData.docsTunnel, sites: harness.model.sites)
        let editor = try #require(model.sheet?.editor)
        editor.routeChecked = true
        let save = model.save(editor)
        #expect(model.operation.isWorking)
        await model.stop(SampleData.previewTunnel)?.value
        #expect(model.stopFailures[SampleData.previewTunnelID] == "The tunnel has not stopped. Retry Stop.")
        #expect(model.banners(for: SampleData.previewTunnelID).map(\.title) == ["The connector did not stop"])
        await gate.open()
        await save?.value
        #expect(model.stopFailures[SampleData.previewTunnelID] != nil)
    }

    @Test("A connector that does not stop at quit opens its own tunnel page")
    func quitFailureOpensTunnel() async {
        let port = InMemoryTunnelsPort()
        let harness = await SitesHarness.launched(tunnels: port)
        await port.configure { $0.stopFails = true }
        #expect(await !harness.model.tunnels.shutdown())
        #expect(harness.model.tunnels.shutdownFailureDestination == .item(.tunnel(SampleData.previewTunnelID)))
    }
}

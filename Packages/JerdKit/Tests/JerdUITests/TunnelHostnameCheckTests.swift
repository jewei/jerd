import Foundation
import JerdTunnels
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Tunnel hostname check", .timeLimit(.minutes(10)))
@MainActor
struct TunnelHostnameCheckTests {
    private let hostname = SampleData.previewTunnel.hostname

    private func launched(_ status: PublicHostnameStatus) async -> SitesHarness {
        let port = InMemoryTunnelsPort()
        await port.configure { [hostname] in $0.hostnameStatuses = [hostname: status] }
        let harness = await SitesHarness.launched(tunnels: port)
        await harness.model.tunnels.hostnameCheck?.value
        return harness
    }

    private func lookups(_ harness: SitesHarness) async -> Int {
        await harness.tunnels.calls.filter { $0 == "look up \(hostname)" }.count
    }

    @Test("A connected tunnel whose hostname has no DNS record shows a warning")
    func missingRecordWarns() async {
        let harness = await launched(.missing)
        let warnings = harness.model.tunnels.hostnameWarnings
        #expect(warnings == [SampleData.previewTunnelID: TunnelMessage.hostnameMissing(hostname)])
        #expect(await !harness.tunnels.calls.contains("look up \(SampleData.docsTunnel.hostname)"))
    }

    @Test("A hostname that resolves shows no warning and is looked up once per connection")
    func resolvingHostnameIsCheckedOnce() async {
        let harness = await launched(.resolves)
        await harness.model.tunnels.refresh()
        await harness.model.tunnels.hostnameCheck?.value
        #expect(harness.model.tunnels.hostnameWarnings.isEmpty)
        #expect(await lookups(harness) == 1)
    }

    @Test("An unknown answer shows no warning and is retried on the next refresh")
    func unknownIsRetried() async {
        let harness = await launched(.unknown)
        let before = await lookups(harness)
        await harness.model.tunnels.refresh()
        await harness.model.tunnels.hostnameCheck?.value
        #expect(harness.model.tunnels.hostnameWarnings.isEmpty)
        #expect(await lookups(harness) == before + 1)
    }

    @Test("Check Again clears the warning after the record exists")
    func checkAgainClearsWarning() async {
        let harness = await launched(.missing)
        await harness.tunnels.configure { [hostname] in $0.hostnameStatuses = [hostname: .resolves] }
        await harness.model.tunnels.checkHostnameAgain(SampleData.previewTunnelID)?.value
        #expect(harness.model.tunnels.hostnameWarnings.isEmpty)
    }

    @Test("Stop clears the warning, and the next Connect looks up the hostname again")
    func stopClearsWarning() async {
        let harness = await launched(.missing)
        let model = harness.model.tunnels
        await model.stop(SampleData.previewTunnel)?.value
        await model.refresh()
        #expect(model.hostnameWarnings.isEmpty)
        try? await harness.tunnels.connect(id: SampleData.previewTunnelID)
        await model.refresh()
        await model.hostnameCheck?.value
        #expect(model.hostnameWarnings[SampleData.previewTunnelID] != nil)
        #expect(await lookups(harness) == 2)
    }
}

import Foundation
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

@Suite("CA update on the Sites page")
@MainActor
struct SitesModelCAUpdateTests {
    private func legacyHarness() async -> SitesHarness {
        let port = InMemorySitesPort()
        await port.configure { $0.authority = SampleData.legacyAuthority }
        return await SitesHarness.launched(sites: port)
    }

    @Test("A setup that trusts the CA that Caddy made offers the update; Jerd's CA does not")
    func onlyTheLegacyCAOffersTheUpdate() async {
        #expect(await legacyHarness().model.needsCAUpdate)
        #expect(await !SitesHarness.launched().model.needsCAUpdate)
    }

    @Test("Update CA… prepares the new CA, asks with its fingerprint, then migrates and reads the setup again")
    func theUpdateAsksThenMigrates() async {
        let harness = await legacyHarness()
        await harness.model.beginCAUpdate()?.value
        #expect(harness.model.confirmation == .updateCA(fingerprint: SampleData.constrainedCAFingerprint))
        #expect(harness.model.confirmation?.isDestructive == false)
        await harness.model.confirm()?.value
        #expect(await harness.sites.calls.suffix(2) == ["prepare CA migration", "migrate CA"])
        #expect(harness.model.authority?.fingerprint == SampleData.constrainedCAFingerprint)
        #expect(!harness.model.needsCAUpdate)
        #expect(harness.recorder.alerts.isEmpty)
    }
}

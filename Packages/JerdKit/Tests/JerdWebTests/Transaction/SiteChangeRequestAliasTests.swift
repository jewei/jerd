import Foundation
import Testing

@testable import JerdWeb

@Suite struct SiteChangeRequestAliasTests {
    @Test func aRemovedAliasLeavesTheApprovalAndAKeptAliasStays() {
        var site = Samples.site(URL(fileURLWithPath: "/p/app"), hostname: "app.test")
        site.aliases = ["a.app.test", "b.app.test"]
        var edited = site
        edited.aliases = ["b.app.test"]
        let request = SiteChangeRequest(
            previous: Samples.configuration([site]), candidate: Samples.configuration([edited]),
            selection: .keepRunning(startIfStopped: false))
        #expect(request.removedHostnames == ["a.app.test"])
        #expect(request.registeredHostnames == ["app.test", "b.app.test"])
    }
}

/// A removed alias leaves the approved set, and so `/etc/hosts` and the trust, also for a site
/// that does not run.
@Suite struct SiteChangeAliasRemovalTests {
    @Test func savingWithoutAnAliasRemovesItFromTheSetup() async throws {
        let harness = try await TransactionHarness(running: [], approved: ["api.demo.test", "demo.test"])
        defer { harness.remove() }
        var site = harness.site("demo.test")
        site.aliases = ["api.demo.test"]
        guard case .committed = try await harness.transaction.apply(.save(site, confirmed: true)) else {
            Issue.record("Expected a save without approval")
            return
        }
        #expect(await harness.gateway.current.hostnames == ["api.demo.test", "demo.test"])
        site.aliases = []
        _ = try await harness.transaction.apply(.save(site, confirmed: true))
        #expect(await harness.gateway.current.hostnames == ["demo.test"])
        #expect(try await harness.registry.snapshot().sites.first?.aliases == [])
    }
}

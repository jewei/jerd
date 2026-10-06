import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

/// The approval check uses the complete approval rule, CA included, and a rollback that finds
/// the previous run still serving reports no restart problem.
@Suite struct SiteChangeAuthorityTests {
    enum Mismatch: CaseIterable {
        case fingerprint, installationID
    }

    func renameDemo(_ harness: TransactionHarness) async throws -> SiteChangeResult {
        var site = harness.site("demo.test")
        site.displayName = "Renamed"
        return try await harness.transaction.apply(.save(site, confirmed: true))
    }

    @Test(arguments: Mismatch.allCases)
    func anotherApprovedCAAsksForApprovalBeforeAnySaveOrStop(_ mismatch: Mismatch) async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        var status = try FakeSystem.approved(["demo.test"])
        switch mismatch {
        case .fingerprint: status.certificateSHA256 = String(repeating: "0", count: 64)
        case .installationID: status.installationID = UUID()
        }
        await harness.gateway.set(status)
        guard case .needsApproval(let pending) = try await renameDemo(harness) else {
            Issue.record("Expected an approval")
            return
        }
        #expect(pending.setup.hostnames == ["demo.test"])
        #expect(await harness.gateway.prepared == [["demo.test"]])
        #expect(await harness.store.saves == 0)
        #expect(await harness.coordinator.halts == 0)
        #expect(await harness.runningIDs() == [harness.site("demo.test").id])
    }

    @Test func aMissingLocalCAAsksForApprovalWhichPreparesIt() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        await harness.gateway.setLocalAuthority(nil)
        guard case .needsApproval = try await renameDemo(harness) else {
            Issue.record("Expected an approval")
            return
        }
        #expect(await harness.gateway.prepared == [["demo.test"]])
        #expect(await harness.store.saves == 0)
    }

    /// A failure after `removeHostnames` gives the removed hostname back.
    @Test func aFailureAfterRemovingAHostnameRestoresTheHostnameAndTheRun() async throws {
        let harness = try await TransactionHarness(sites: ["demo.test", "two.test"])
        defer { harness.remove() }
        await harness.coordinator.failActivations(1)
        await #expect {
            try await harness.transaction.apply(.remove(harness.site("two.test").id))
        } throws: { error in
            FailureDetail.describe(error).hasPrefix("The site change failed. The previous settings were restored.")
        }
        #expect(await harness.gateway.current.hostnames == ["demo.test", "two.test"])
        #expect(await harness.gateway.restores == 1)
        #expect(try await harness.registry.snapshot() == harness.before)
        #expect(await harness.runningIDs() == Set(harness.before.sites.map(\.id)))
    }

    /// The real coordinator refuses an activation before it stops anything (here: the CA file
    /// changed after S3). The rollback finds the previous run still serving and keeps it.
    @Test func aRefusedActivationKeepsThePreviousRunWithoutARestartProblem() async throws {
        let live = try await LiveTransaction(sites: ["demo.test", "two.test"], running: ["demo.test"])
        defer { live.harness.remove() }
        await live.store.pauseNextSave()
        let edit = Task { try await live.transaction.apply(.enabled(live.site("two.test").id, true)) }
        #expect(await waitUntil { await live.store.isPaused })
        try AtomicFile.write(try Certificates.pem("other-ca"), to: live.harness.layout.environment.rootCertificateFile)
        await live.store.resume()
        await #expect {
            try await edit.value
        } throws: { error in
            FailureDetail.describe(error)
                == "The site change failed. The previous settings were restored. The local CA does not match the "
                + "approved HTTPS setup. The active sites were kept running."
        }
        #expect(await live.harness.coordinator.snapshot().siteIDs == [live.site("demo.test").id])
        #expect(await live.harness.engine.starts == 1)
        #expect(try await live.registry.snapshot() == live.before)
    }
}

/// A transaction over the real coordinator and gateway, with the coordinator harness's fakes.
struct LiveTransaction {
    let harness: CoordinatorHarness
    let store: FakeConfigurationStore
    let registry: SiteRegistry
    let transaction: SiteChangeTransaction
    let before: AppConfiguration

    /// `sites` are approved; the ones in `running` run, and the others are disabled.
    init(sites hostnames: [String], running: [String]) async throws {
        harness = try CoordinatorHarness(approved: hostnames)
        var sites: [Site] = []
        for host in hostnames {
            var site = try harness.site(host)
            site.isEnabled = running.contains(host)
            sites.append(site)
        }
        before = AppConfiguration(
            sites: sites, runtimes: [harness.runtime], defaultRuntimeID: harness.runtime.id, caddy: harness.caddy)
        store = FakeConfigurationStore(before)
        registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let gateway = SystemSetupGateway(
            layout: harness.layout, system: harness.system, coordinator: harness.coordinator)
        transaction = SiteChangeTransaction(
            registry: registry, reducer: SiteChangeReducer(hosts: FakeHostsFile()), coordinator: harness.coordinator,
            gateway: gateway)
        let ids = Set(sites.filter(\.isEnabled).map(\.id))
        try await harness.ensure(try ServingPlan(before, siteIDs: ids))
    }

    func site(_ hostname: String) -> Site { before.sites.first { $0.hostname == hostname }! }
}

import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SiteChangeApprovalTests {
    func hostnameEdit(_ harness: TransactionHarness) async throws -> PendingSiteChange {
        var site = harness.site("demo.test")
        site.hostname = "changed.test"
        guard case .needsApproval(let pending) = try await harness.transaction.apply(.save(site, confirmed: true))
        else {
            throw JerdError.invalid("Expected approval")
        }
        return pending
    }

    @Test func approvalIsAskedBeforeAnySaveOrStopAndCoversDisabledSites() async throws {
        let harness = try await TransactionHarness(sites: ["demo.test", "off.test"], running: ["demo.test"])
        defer { harness.remove() }
        _ = try await harness.transaction.apply(.enabled(harness.site("off.test").id, false))
        let pending = try await hostnameEdit(harness)
        #expect(pending.setup.hostnames == ["changed.test", "off.test"])
        #expect(await harness.store.saves == 1)
        #expect(await harness.gateway.applications == 0)
        #expect(await harness.transaction.trace.last == .awaitingApproval)
        #expect(await harness.runningIDs() == [harness.site("demo.test").id])
    }

    @Test func anApprovedChangeRunsWithOnePreflightInTotal() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let pending = try await hostnameEdit(harness)
        let saved = try await harness.transaction.approve(pending)
        #expect(saved.sites[0].hostname == "changed.test")
        #expect(await harness.coordinator.preflights == 1)
        #expect(await harness.gateway.applications == 1)
        #expect(await harness.runningIDs() == [harness.site("demo.test").id])
    }

    @Test(arguments: [false, true])
    func aFailedSaveOrActivationRestoresSettingsSetupAndTheRunOnce(_ saveFails: Bool) async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let pending = try await hostnameEdit(harness)
        if saveFails { await harness.store.failNextSave() } else { await harness.coordinator.failActivations(1) }
        do {
            _ = try await harness.transaction.approve(pending)
            Issue.record("Expected a failure")
        } catch {
            #expect(
                FailureDetail.describe(error).hasPrefix("The site change failed. The previous settings were restored."))
            #expect(!FailureDetail.describe(error).contains("Site activation failed"))
        }
        #expect(try await harness.registry.snapshot() == harness.before)
        #expect(await harness.gateway.current.hostnames == ["demo.test"])
        #expect(await harness.runningIDs() == [harness.site("demo.test").id])
        #expect(await harness.coordinator.launches == (saveFails ? 1 : 2))
        #expect(await harness.transaction.trace.suffix(2) == [.rollingBack, .reporting])
    }

    @Test func aFailedRestoreIsReportedOnceWithEveryProblem() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let pending = try await hostnameEdit(harness)
        await harness.coordinator.failActivations(2)
        await harness.gateway.failNextRestore()
        do {
            _ = try await harness.transaction.approve(pending)
            Issue.record("Expected a failure")
        } catch {
            let message = FailureDetail.describe(error)
            #expect(message.hasPrefix("The site change failed: Test failed launch Recovery needs attention."))
            #expect(message.contains("HTTPS: Test restore failure") && message.contains("Restart: Test failed launch"))
        }
        #expect(try await harness.registry.snapshot() == harness.before)
    }

    @Test func anApprovalAfterAnotherSettingsChangeIsRefusedWithoutSystemChange() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let pending = try await hostnameEdit(harness)
        _ = try await harness.transaction.apply(.caddy(Samples.caddy(path: "/other")))
        await #expect(throws: JerdError.unavailable("The site settings changed. Save and approve the edit again.")) {
            try await harness.transaction.approve(pending)
        }
        #expect(await harness.gateway.applications == 0)
    }

    @Test func anApprovalForOtherHostnamesIsRefusedBeforeAnyEffect() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let pending = try await hostnameEdit(harness)
        let wrong = PendingSiteChange(
            setup: try await harness.gateway.prepare(hostnames: ["other.test"], caddy: Samples.caddy()),
            request: pending.request, prepared: pending.prepared)
        await #expect(throws: JerdError.invalid("The approved hostnames do not match the edit.")) {
            try await harness.transaction.approve(wrong)
        }
        #expect(await harness.gateway.applications == 0)
        #expect(await harness.store.saves == 0)
    }

    @Test func aStopDuringTheSystemRollbackPreventsTheRestart() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let pending = try await hostnameEdit(harness)
        await harness.coordinator.failActivations(1)
        await harness.gateway.holdNextRestore()
        let approval = Task { try await harness.transaction.approve(pending) }
        #expect(await waitUntil { await harness.gateway.isRestoring })
        await harness.transaction.requestStop()
        await harness.gateway.resume()
        await #expect(throws: (any Error).self) { try await approval.value }
        #expect(try await harness.registry.snapshot() == harness.before)
        #expect(await harness.gateway.current.hostnames == ["demo.test"])
        #expect(await harness.coordinator.launches == 1)
        #expect(await harness.runningIDs() == nil)
    }

    @Test func aStopDuringPreparationEndsTheChangeWithoutAnyEffect() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        await harness.coordinator.holdNextPreflight()
        let change = Task { try await harness.transaction.apply(.caddy(Samples.caddy(path: "/changed"))) }
        #expect(await waitUntil { await harness.coordinator.isWaitingInPreflight })
        await harness.transaction.requestStop()
        await #expect(throws: CancellationError.self) { try await change.value }
        #expect(try await harness.registry.snapshot() == harness.before)
        #expect(await harness.coordinator.launches == 0)
    }

    @Test func aStopBeforeAChangeBeginsDoesNotCancelIt() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        await harness.transaction.requestStop()
        _ = try await harness.transaction.apply(.caddy(Samples.caddy(path: "/changed")))
        _ = try await harness.transaction.run([harness.site("demo.test").id])
        #expect(await harness.coordinator.running?.caddy.path == "/changed")
    }
}

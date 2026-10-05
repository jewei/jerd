import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SiteChangeTransactionTests {
    @Test func anUnchangedConfigurationCommitsAtOnce() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let result = try await harness.transaction.apply(.remove(UUID()))
        guard case .committed(let configuration) = result else {
            Issue.record("Expected a commit")
            return
        }
        #expect(configuration == harness.before)
        #expect(await harness.transaction.trace == [.noChange])
        #expect(await harness.store.saves == 0)
    }

    @Test func aDisplayNameEditSavesWithoutPreflightLaunchOrStop() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        var renamed = harness.site("demo.test")
        renamed.displayName = "Renamed"
        _ = try await harness.transaction.apply(.save(renamed, confirmed: true))
        #expect(await harness.coordinator.preflights == 0)
        #expect(await harness.coordinator.launches == 0)
        #expect(await harness.coordinator.halts == 0)
        #expect(try await harness.registry.snapshot().sites[0].displayName == "Renamed")
        #expect(
            await harness.transaction.trace == [
                .planning, .recoveryGate, .preparing, .stopGate, .committing, .committed,
            ])
    }

    @Test func savingADisabledSiteDoesNotNeedCaddyOrStartAnything() async throws {
        let harness = try await TransactionHarness(sites: [], approved: [])
        defer { harness.remove() }
        var site = Samples.site(try harness.folder.folder("new"), hostname: "new.test")
        site.isEnabled = false
        _ = try await harness.transaction.apply(.save(site, confirmed: true), startIfStopped: true)
        #expect(try await harness.registry.snapshot().sites.map(\.id) == [site.id])
        #expect(await harness.coordinator.launches == 0)
    }

    @Test(arguments: ["edit", "caddy", "remove", "disable"])
    func changesKeepExactlyTheRunningSubset(_ change: String) async throws {
        let harness = try await TransactionHarness(sites: ["active.test", "stopped.test"], running: ["active.test"])
        defer { harness.remove() }
        let active = harness.site("active.test")
        switch change {
        case "edit":
            var edited = harness.site("stopped.test")
            edited.displayName = "Still stopped"
            _ = try await harness.transaction.apply(.save(edited, confirmed: true))
        case "caddy":
            _ = try await harness.transaction.apply(.caddy(Samples.caddy(path: "/new-caddy")))
        case "remove":
            _ = try await harness.transaction.apply(.remove(active.id))
        default:
            _ = try await harness.transaction.apply(.enabled(active.id, false))
        }
        let expected: Set<UUID>? = ["remove", "disable"].contains(change) ? nil : [active.id]
        #expect(await harness.runningIDs() == expected)
    }

    @Test func aNewSiteJoinsARunAndANewSiteWithoutARunStartsOnlyWhenAsked() async throws {
        let harness = try await TransactionHarness(sites: ["active.test"], approved: ["active.test", "new.test"])
        defer { harness.remove() }
        let new = Samples.site(try harness.folder.folder("new"), hostname: "new.test")
        _ = try await harness.transaction.apply(.save(new, confirmed: true))
        #expect(await harness.runningIDs() == [harness.site("active.test").id, new.id])
        let stopped = try await TransactionHarness(sites: [], approved: ["new.test"])
        defer { stopped.remove() }
        let other = Samples.site(try stopped.folder.folder("new"), hostname: "new.test")
        _ = try await stopped.transaction.apply(.save(other, confirmed: true))
        #expect(await stopped.runningIDs() == nil)
        let third = Samples.site(try stopped.folder.folder("third"), hostname: "new.test", id: other.id)
        _ = try await stopped.transaction.apply(.save(third, confirmed: true), startIfStopped: true)
        #expect(await stopped.runningIDs() == nil)
    }

    @Test(arguments: [false, true])
    func invalidEditsAndPreflightFailuresKeepSettingsAndTheRun(_ preflightFails: Bool) async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        await harness.coordinator.failNextPreflight()
        var site = harness.site("demo.test")
        if preflightFails {
            site.documentRoot = try harness.folder.folder("projects/demo.test/public").path
        } else {
            site.documentRoot = "/missing"
        }
        await #expect(throws: JerdError.self) { try await harness.transaction.apply(.save(site, confirmed: true)) }
        #expect(try await harness.registry.snapshot() == harness.before)
        #expect(await harness.runningIDs() == [site.id])
        #expect(await harness.coordinator.halts == 0)
        #expect(await harness.coordinator.launches == 0)
    }

    @Test func aPendingRecoveryBlocksEveryChange() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        var status = try FakeSystem.approved(["demo.test"])
        status.hasPendingRecovery = true
        await harness.gateway.set(status)
        await #expect(
            throws: JerdError.unavailable("Recover the interrupted HTTPS setup in Advanced before changing sites.")
        ) { try await harness.transaction.apply(.caddy(Samples.caddy(path: "/new"))) }
        #expect(await harness.transaction.trace == [.planning, .recoveryGate])
        #expect(await harness.store.saves == 0)
    }

    @Test func aRenamedStoppedSiteLeavesTheApprovedHostnames() async throws {
        let harness = try await TransactionHarness(sites: ["a.test", "b.test"], running: ["a.test"])
        defer { harness.remove() }
        var renamed = harness.site("b.test")
        renamed.hostname = "c.test"
        _ = try await harness.transaction.apply(.save(renamed, confirmed: true))
        #expect(await harness.gateway.current.hostnames == ["a.test"])
        #expect(try await harness.registry.snapshot().sites[1].hostname == "c.test")
    }

    @Test func aRuntimeUpdateOfTheRunningRuntimeReplansTheRun() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        let updated = Samples.runtime(version: "8.4.1")
        _ = try await harness.transaction.apply(.upsertRuntime(updated))
        #expect(await harness.coordinator.preflights == 1)
        #expect(await harness.coordinator.launches == 1)
        #expect(await harness.coordinator.running?.sites[0].runtime.version == "8.4.1")
    }

    @Test func aSecondChangeDuringOneIsRefused() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        await harness.coordinator.holdNextPreflight()
        let first = Task { try await harness.transaction.apply(.caddy(Samples.caddy(path: "/new"))) }
        #expect(await waitUntil { await harness.coordinator.isWaitingInPreflight })
        await #expect(throws: JerdError.unavailable("Wait for the current site edit.")) {
            try await harness.transaction.apply(.caddy(Samples.caddy(path: "/other")))
        }
        await harness.transaction.requestStop()
        await #expect(throws: CancellationError.self) { try await first.value }
    }

    @Test func runSelectsExactlyTheEnabledSitesAndAnEmptySelectionStops() async throws {
        let harness = try await TransactionHarness(sites: ["a.test", "b.test"], running: [])
        defer { harness.remove() }
        let a = harness.site("a.test")
        _ = try await harness.transaction.run([a.id])
        #expect(await harness.runningIDs() == [a.id])
        _ = try await harness.transaction.run([])
        #expect(await harness.runningIDs() == nil)
        #expect(try await harness.registry.snapshot() == harness.before)
        await #expect(throws: JerdError.invalid("The selected sites changed or are disabled. Select the sites again."))
        {
            try await harness.transaction.run([UUID()])
        }
    }
}

import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

/// Forwarded hosts reach the run only through the transaction: a site change reads them and never
/// fails because of them, and a forwarder's apply restarts the run only for a changed mapping.
@Suite(.timeLimit(.minutes(1))) struct SiteChangeForwardedHostTests {
    private let publicHost = PublicHostname("public.example.com")!

    private func running(
        _ hostnames: [String] = ["demo.test"], serving: [String]? = nil
    ) async throws
        -> LiveTransaction
    {
        try await LiveTransaction(sites: hostnames, running: serving ?? hostnames)
    }

    @Test func aNewForwardedHostRestartsTheRunWithIt() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        let preflights = await live.harness.engine.preflights
        await live.forwardedHosts.set(demo.id, [publicHost.value])
        let served = try await live.transaction.applyForwardedHosts(servingSite: demo.id)
        #expect(served == demo)
        #expect(await live.harness.engine.starts == 2)
        #expect(await live.harness.engine.preflights == preflights + 1)
        #expect(await live.harness.coordinator.runningPlan()?.forwardedHosts.hosts(of: demo.id) == [publicHost])
        #expect(await live.harness.coordinator.snapshot().state == .running)
    }

    @Test func anUnchangedMappingNeverRestartsTheRun() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        let preflights = await live.harness.engine.preflights
        #expect(try await live.transaction.applyForwardedHosts(servingSite: demo.id) == demo)
        #expect(await live.harness.engine.starts == 1)
        #expect(await live.harness.engine.preflights == preflights)
    }

    @Test func aSiteThatTheRunDoesNotServeGivesNilAndStartsNothing() async throws {
        let live = try await running(["demo.test", "two.test"], serving: ["demo.test"])
        defer { live.harness.remove() }
        let two = live.site("two.test")
        await live.forwardedHosts.set(two.id, [publicHost.value])
        #expect(try await live.transaction.applyForwardedHosts(servingSite: two.id) == nil)
        #expect(try await live.transaction.applyForwardedHosts(servingSite: UUID()) == nil)
        #expect(await live.harness.engine.starts == 1)
        #expect(await live.forwardedHosts.reads == 0)
    }

    @Test func anUnreadableRouteFileFailsTheApplyAndKeepsTheRun() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        await live.forwardedHosts.failReads()
        await #expect(throws: FakeForwardedHosts.readFailure) {
            try await live.transaction.applyForwardedHosts(servingSite: live.site("demo.test").id)
        }
        #expect(await live.harness.engine.starts == 1)
        #expect(await live.harness.coordinator.snapshot().state == .running)
    }

    @Test func aFailedRestartRestoresThePreviousRunOnce() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        await live.forwardedHosts.set(demo.id, [publicHost.value])
        await live.harness.engine.rejectNextStart()
        await #expect {
            try await live.transaction.applyForwardedHosts(servingSite: demo.id)
        } throws: { error in
            (error as? JerdError)?.message.hasPrefix("The site change failed. The previous settings were restored.")
                == true
        }
        #expect(await live.harness.engine.starts == 3)
        #expect(await live.harness.coordinator.runningPlan()?.forwardedHosts == ForwardedHosts.none)
        #expect(await live.harness.coordinator.snapshot().siteIDs == [demo.id])
    }

    /// Regression test: a tunnel Stop cancels its launch. That cancellation used to reach the
    /// restart after the old run stopped, so every site stopped and nothing restarted it.
    @Test func aCancelledCallerDoesNotStopTheSites() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        await live.forwardedHosts.set(demo.id, [publicHost.value])
        await live.harness.engine.holdNextStart()
        let transaction = live.transaction
        let apply = Task { try await transaction.applyForwardedHosts(servingSite: demo.id) }
        #expect(await waitUntil { await live.harness.engine.isHolding })
        apply.cancel()
        await live.harness.engine.resumeHeld()
        _ = await apply.result
        #expect(await live.harness.coordinator.snapshot() == EnvironmentSnapshot(state: .running, siteIDs: [demo.id]))
        #expect(await live.harness.coordinator.runningPlan()?.forwardedHosts.hosts(of: demo.id) == [publicHost])
    }

    /// A Connect during a site change waits for it instead of failing with "Wait for the
    /// current site edit.", and it never cuts into it.
    @Test func theApplyWaitsForASiteChangeThatRuns() async throws {
        let live = try await running(["demo.test", "two.test"], serving: ["demo.test"])
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        let two = live.site("two.test")
        await live.harness.engine.holdNextPreflight()
        let transaction = live.transaction
        let change = Task { try await transaction.apply(.enabled(two.id, true)) }
        #expect(await waitUntil { await live.harness.engine.isHolding })
        let apply = Task { try await transaction.applyForwardedHosts(servingSite: two.id) }
        let gate = await transaction.gate
        #expect(await waitUntil { gate.waiterCount == 1 })
        await live.harness.engine.resumeHeld()
        _ = try await change.value
        #expect(try await apply.value?.id == two.id)
        #expect(await live.harness.coordinator.snapshot().siteIDs == [demo.id, two.id])
    }

    @Test func aSiteStartServesTheSavedForwardedHosts() async throws {
        let harness = try await TransactionHarness(running: [])
        defer { harness.remove() }
        let demo = harness.site("demo.test")
        await harness.forwardedHosts.set(demo.id, [publicHost.value])
        _ = try await harness.transaction.run([demo.id])
        #expect(await harness.coordinator.running?.forwardedHosts.hosts(of: demo.id) == [publicHost])
    }

    /// Tunnel settings are not site settings: a file that cannot be read must not block a site.
    @Test func unreadableRoutesNeverBlockStartingASite() async throws {
        let harness = try await TransactionHarness(running: [])
        defer { harness.remove() }
        await harness.forwardedHosts.failReads()
        let demo = harness.site("demo.test")
        _ = try await harness.transaction.run([demo.id])
        #expect(await harness.coordinator.running?.siteIDs == [demo.id])
        #expect(await harness.coordinator.running?.forwardedHosts == ForwardedHosts.none)
    }

    @Test func unreadableRoutesKeepTheForwardedHostsOfTheRun() async throws {
        let harness = try await TransactionHarness(sites: ["demo.test", "two.test"], running: [])
        defer { harness.remove() }
        let demo = harness.site("demo.test")
        await harness.forwardedHosts.set(demo.id, [publicHost.value])
        _ = try await harness.transaction.run([demo.id])
        await harness.forwardedHosts.failReads()
        _ = try await harness.transaction.run([demo.id, harness.site("two.test").id])
        #expect(await harness.coordinator.running?.siteIDs.count == 2)
        #expect(await harness.coordinator.running?.forwardedHosts.hosts(of: demo.id) == [publicHost])
    }

    /// Regression test: a plan from the configuration had no forwarded hosts, so it never equaled
    /// a run with them, and every edit ran a preflight that it did not need.
    @Test func anEditThatServesTheSameWayNeedsNoPreflight() async throws {
        let harness = try await TransactionHarness(running: [])
        defer { harness.remove() }
        var demo = harness.site("demo.test")
        await harness.forwardedHosts.set(demo.id, [publicHost.value])
        _ = try await harness.transaction.run([demo.id])
        let preflights = await harness.coordinator.preflights
        demo.displayName = "Renamed"
        _ = try await harness.transaction.apply(.save(demo, confirmed: true))
        #expect(await harness.coordinator.preflights == preflights)
        #expect(await harness.coordinator.launches == 1)
    }

    @Test func aPendingRecoveryRefusesTheRestartAndKeepsTheRun() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        await live.forwardedHosts.set(demo.id, [publicHost.value])
        var status = try FakeSystem.approved(["demo.test"])
        status.hasPendingRecovery = true
        await live.harness.system.set(status)
        await #expect(
            throws: JerdError.unavailable("Recover the interrupted HTTPS setup in Advanced before connecting.")
        ) {
            try await live.transaction.applyForwardedHosts(servingSite: demo.id)
        }
        #expect(await live.harness.engine.starts == 1)
        #expect(await live.harness.coordinator.snapshot().state == .running)
    }

    /// The user's Stop during the restart ends it, and the rollback does not start the run again.
    @Test func aUserStopDuringTheRestartStopsTheSites() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        await live.forwardedHosts.set(demo.id, [publicHost.value])
        await live.harness.engine.holdNextStart()
        let transaction = live.transaction
        let apply = Task { try await transaction.applyForwardedHosts(servingSite: demo.id) }
        #expect(await waitUntil { await live.harness.engine.isHolding })
        let stop = Task { await transaction.requestStop() }
        #expect(await waitUntil { await live.harness.coordinator.isStopRequested(since: StopTicket(epoch: 0)) })
        await live.harness.engine.resumeHeld()
        await #expect(throws: CancellationError.self) { try await apply.value }
        await stop.value
        #expect(await live.harness.engine.starts == 2)
        #expect(await live.harness.coordinator.snapshot().state == .stopped)
        #expect(await transaction.servedHostnames.isEmpty)
    }

    @Test func theServedSitesAreRecordedWhenAChangeEnds() async throws {
        let harness = try await TransactionHarness(sites: ["demo.test", "two.test"], running: [])
        defer { harness.remove() }
        let demo = harness.site("demo.test")
        #expect(await harness.transaction.servedHostnames.isEmpty)
        _ = try await harness.transaction.run([demo.id])
        #expect(await harness.transaction.servedHostnames == [demo.id: "demo.test"])
        await harness.transaction.requestStop()
        #expect(await harness.transaction.servedHostnames.isEmpty)
    }

    /// Regression test: a change that was refused during a restart read the run while it served
    /// no site, and the tunnels of every site stopped.
    @Test func aRefusedChangeDuringARestartKeepsTheServedSites() async throws {
        let live = try await running()
        defer { live.harness.remove() }
        let demo = live.site("demo.test")
        _ = try await live.transaction.run([demo.id])
        await live.forwardedHosts.set(demo.id, [publicHost.value])
        await live.harness.engine.holdNextStart()
        let transaction = live.transaction
        let apply = Task { try await transaction.applyForwardedHosts(servingSite: demo.id) }
        #expect(await waitUntil { await live.harness.engine.isHolding })
        #expect(await live.harness.coordinator.runningPlan() == nil)
        await #expect(throws: JerdError.unavailable("Wait for the current site edit.")) {
            try await transaction.run([demo.id])
        }
        #expect(await transaction.servedHostnames == [demo.id: "demo.test"])
        await live.harness.engine.resumeHeld()
        _ = try await apply.value
        #expect(await transaction.servedHostnames == [demo.id: "demo.test"])
    }
}

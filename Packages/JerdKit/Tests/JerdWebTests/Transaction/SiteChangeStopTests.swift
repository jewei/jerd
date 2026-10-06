import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

/// When a change takes its stop ticket, and what the transaction's
/// Stop does.
@Suite struct SiteChangeStopTests {
    /// The ticket is taken before the first suspension, so a Stop while the change reads the
    /// settings counts as a Stop during the change.
    @Test func aStopWhileTheChangeReadsTheSettingsCancelsIt() async throws {
        let hosts = BlockingHostsFile()
        let harness = try await TransactionHarness(
            sites: ["demo.test"], running: [], approved: ["demo.test", "new.test"], hosts: hosts)
        defer { harness.remove() }
        let site = Samples.site(try harness.folder.folder("projects/new.test"), hostname: "new.test")
        let change = Task { try await harness.transaction.apply(.save(site, confirmed: true), startIfStopped: true) }
        #expect(await waitUntil { hosts.isReading })
        await harness.coordinator.requestStop()
        hosts.release()
        await #expect(throws: CancellationError.self) { try await change.value }
        #expect(await harness.runningIDs() == nil)
        #expect(await harness.coordinator.launches == 0)
        #expect(try await harness.registry.snapshot() == harness.before)
    }

    /// The transaction's Stop ends the change, prevents its restart, and stops the run.
    @Test func theTransactionStopEndsTheChangeAndStopsTheRun() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        await harness.coordinator.holdNextPreflight()
        let change = Task { try await harness.transaction.apply(.caddy(Samples.caddy(path: "/changed"))) }
        #expect(await waitUntil { await harness.coordinator.isWaitingInPreflight })
        await harness.transaction.requestStop()
        await #expect(throws: CancellationError.self) { try await change.value }
        #expect(await harness.coordinator.stops == 1)
        #expect(await harness.runningIDs() == nil)
        #expect(await harness.coordinator.launches == 0)
    }

    /// Without a change, the transaction's Stop still stops the run.
    @Test func theTransactionStopStopsAnIdleRun() async throws {
        let harness = try await TransactionHarness()
        defer { harness.remove() }
        await harness.transaction.requestStop()
        #expect(await harness.runningIDs() == nil)
        #expect(await harness.coordinator.stops == 1)
    }
}

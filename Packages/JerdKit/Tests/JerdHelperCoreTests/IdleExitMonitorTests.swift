import Foundation
import JerdSystem
import Testing
import os

@testable import JerdHelperCore

/// The helper ends when it is idle, so launchd starts the current file after an app update. Each
/// `check` stands for one `checkInterval` of a fake clock; no test waits for real time.
@Suite(.timeLimit(.minutes(1))) struct IdleExitMonitorTests {
    private static let checksToExit = Int(IdleExitMonitor.idleLimit / IdleExitMonitor.checkInterval)

    private func monitor(
        _ lifetime: HelperLifetime, busy: OSAllocatedUnfairLock<[Bool]> = .init(initialState: []),
        replaced: Bool = false
    ) -> IdleExitMonitor {
        IdleExitMonitor(
            lifetime: lifetime,
            isBusy: { busy.withLock { $0.isEmpty ? false : $0.removeFirst() } },
            isReplaced: { replaced }, sleep: { _ in }, exit: {})
    }

    /// The number of idle checks until `check` returns true, at most `limit`.
    private func checksUntilExit(_ monitor: IdleExitMonitor, limit: Int = 100) async -> Int? {
        var progress = IdleExitMonitor.Progress(generation: monitor.lifetime.snapshot.generation)
        for count in 1...limit where await monitor.check(&progress) { return count }
        return nil
    }

    @Test func theIdleLimitIsAboveTheLaunchdRespawnThrottleAndShort() {
        #expect(IdleExitMonitor.idleLimit >= .seconds(30) && IdleExitMonitor.idleLimit <= .seconds(60))
        #expect(Self.checksToExit == 6)
    }

    @Test func anIdleHelperExitsAfterTheIdleLimitAndThenRefusesConnections() async {
        let lifetime = HelperLifetime()
        #expect(await checksUntilExit(monitor(lifetime)) == Self.checksToExit)
        #expect(lifetime.snapshot.isExiting)
        #expect(lifetime.open() == nil)
    }

    @Test func anOpenConnectionKeepsTheHelper() async {
        let lifetime = HelperLifetime()
        let ticket = lifetime.open()
        #expect(await checksUntilExit(monitor(lifetime), limit: 50) == nil)
        ticket?.close()
        #expect(await checksUntilExit(monitor(lifetime)) == Self.checksToExit)
    }

    @Test func aConnectionBetweenTwoChecksStartsTheIdleTimeAgain() async {
        let lifetime = HelperLifetime()
        let monitor = monitor(lifetime)
        var progress = IdleExitMonitor.Progress()
        for _ in 1..<Self.checksToExit { #expect(await !monitor.check(&progress)) }
        lifetime.open()?.close()
        #expect(await !monitor.check(&progress))
        #expect(progress.quiet == .zero)
        for _ in 1..<Self.checksToExit { #expect(await !monitor.check(&progress)) }
        #expect(await monitor.check(&progress))
    }

    @Test func aLeaseOrATransactionKeepsTheHelperWithoutConnections() async {
        let lifetime = HelperLifetime()
        let busy = OSAllocatedUnfairLock(initialState: Array(repeating: true, count: 40))
        #expect(await checksUntilExit(monitor(lifetime, busy: busy), limit: 40) == nil)
        #expect(!lifetime.snapshot.isExiting)
    }

    @Test func workThatStartsAtTheExitCancelsItAndAcceptsConnectionsAgain() async {
        let lifetime = HelperLifetime()
        // Idle on every regular check, busy on the last check after `beginExit`.
        let busy = OSAllocatedUnfairLock(
            initialState: Array(repeating: false, count: Self.checksToExit) + [true])
        let monitor = monitor(lifetime, busy: busy)
        var progress = IdleExitMonitor.Progress()
        for _ in 1...Self.checksToExit { #expect(await !monitor.check(&progress)) }
        #expect(!lifetime.snapshot.isExiting)
        #expect(lifetime.open() != nil)
    }

    @Test func aReplacedExecutableExitsAtTheFirstIdleCheck() async {
        let lifetime = HelperLifetime()
        #expect(await checksUntilExit(monitor(lifetime, replaced: true)) == 1)
        let busyLifetime = HelperLifetime()
        let busy = OSAllocatedUnfairLock(initialState: Array(repeating: true, count: 20))
        #expect(await checksUntilExit(monitor(busyLifetime, busy: busy, replaced: true), limit: 20) == nil)
    }

    @Test func aTicketCountsItsConnectionOnce() {
        let lifetime = HelperLifetime()
        let first = lifetime.open()
        let second = lifetime.open()
        first?.close()
        first?.close()
        #expect(lifetime.snapshot.connections == 1)
        second?.close()
        #expect(lifetime.snapshot.connections == 0 && lifetime.snapshot.generation == 4)
    }

    @Test func runEndsTheProcessOnlyAfterTheIdleLimit() async {
        let lifetime = HelperLifetime()
        let sleeps = OSAllocatedUnfairLock(initialState: [Duration]())
        let exits = OSAllocatedUnfairLock(initialState: 0)
        let monitor = IdleExitMonitor(
            lifetime: lifetime, isBusy: { false }, isReplaced: { false },
            sleep: { duration in
                // A bound, so a regression that never exits ends the run instead of hanging the test.
                let count = sleeps.withLock { current -> Int in
                    current.append(duration)
                    return current.count
                }
                if count > 100 { throw CancellationError() }
            }, exit: { exits.withLock { $0 += 1 } })
        await monitor.run()
        #expect(exits.withLock { $0 } == 1)
        #expect(sleeps.withLock { $0 } == Array(repeating: IdleExitMonitor.checkInterval, count: Self.checksToExit))
    }

    @Test func aCancelledRunNeverEndsTheProcess() async {
        let exits = OSAllocatedUnfairLock(initialState: 0)
        let monitor = IdleExitMonitor(
            lifetime: HelperLifetime(), isBusy: { false }, isReplaced: { false },
            sleep: { _ in throw CancellationError() }, exit: { exits.withLock { $0 += 1 } })
        await monitor.run()
        #expect(exits.withLock { $0 } == 0)
    }

    @Test func theServiceIsBusyDuringALeaseAndDuringATransaction() async throws {
        let harness = try ServiceHarness()
        defer { harness.remove() }
        let service = harness.service
        #expect(await !service.isBusy)
        let held = HeldConsent(harness.consent)
        let payload = try harness.request()
        let configure = Task { try await service.configure(payload, owner: ServiceHarness.owner, consent: held) }
        await held.waitUntilAsked()
        #expect(await service.isBusy)
        held.release()
        try await configure.value
        #expect(await !service.isBusy)
        let connection = UUID()
        let pair = try await service.acquire(
            owner: ServiceHarness.owner, connection: connection, lifetime: SessionLifetime())
        #expect(await service.isBusy)
        await service.release(connection: connection)
        #expect(await !service.isBusy)
        pair.close()
    }

    @Test func theExecutableIdentityNoticesAReplacedOrRemovedFile() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("jerd-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("JerdHelper")
        try Data("old".utf8).write(to: file)
        let identity = try #require(ExecutableFileIdentity.of(file.path))
        #expect(!identity.isReplaced)
        let update = folder.appendingPathComponent("JerdHelper.new")
        try Data("new".utf8).write(to: update)
        #expect(rename(update.path, file.path) == 0)
        #expect(identity.isReplaced)
        try FileManager.default.removeItem(at: file)
        #expect(identity.isReplaced)
        #expect(ExecutableFileIdentity.current() != nil)
    }
}

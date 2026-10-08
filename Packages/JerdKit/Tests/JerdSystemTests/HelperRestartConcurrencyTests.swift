import Foundation
import JerdFoundation
import Testing
import os

@testable import JerdSystem

/// Calls that overlap a helper restart (automatic or Reconnect Helper). The restart pauses on a
/// `PauseGate`, so each test starts its other calls in the middle of it.
@Suite(.timeLimit(.minutes(1))) struct HelperRestartConcurrencyTests {
    /// Regression test: the restart closes the old link, which fails a call in flight with 4099.
    /// The call waits for the restart before it sends again; before, it sent at once and failed
    /// with "Approved helper setup is required." and no remedy.
    @Test func aCallInFlightWhenARestartStartsIsSentAgainAfterIt() async throws {
        let helper = try RecoveryFixture.configuredHelper()
        helper.script.withLock { $0.unanswered = true }
        let daemon = FakeDaemonService(.enabled)
        daemon.configure { $0.exitingChecks = 1 }
        let gate = PauseGate()
        let (client, _) = RecoveryFixture.client(
            helper, daemon: daemon, script: .init(currentAfterRegistrations: 0), gate: gate)
        let inFlight = Task { try await client.status() }
        await RecoveryFixture.until { helper.calls.count == 1 }
        let reconnect = Task { try await client.reconnect() }
        await gate.waitUntilPaused()
        await RecoveryFixture.settle()
        helper.script.withLock { $0.unanswered = false }
        gate.open()
        let status = try await inFlight.value
        #expect(status.availability == .enabled && status.setup.hostnames == ["games-jp.test"])
        try await reconnect.value
        #expect(daemon.calls == ["unregister", "register"])
    }

    /// A late 4099 of an old link closes only that link, never the newer link that other calls use.
    @Test func aLateFailureOfAnOldLinkDoesNotCloseTheNewLink() async throws {
        let helper = try RecoveryFixture.configuredHelper()
        let daemon = FakeDaemonService(.enabled)
        let (client, opener) = RecoveryFixture.client(
            helper, daemon: daemon, script: .init(currentAfterRegistrations: 0, heldCalls: 1))
        let early = Task { try await client.status() }
        await RecoveryFixture.until { opener.heldCount == 1 }
        await client.invalidate()
        helper.script.withLock { $0.unanswered = true }
        let waiting = Task { try await client.status() }
        await RecoveryFixture.until { helper.calls.count == 1 }
        helper.script.withLock { $0.unanswered = false }
        opener.releaseHeldFailures(code: HelperTransportError.invalidCode)
        #expect(try await early.value.setup.hostnames == ["games-jp.test"])
        #expect(opener.invalidated == 1)
        await client.invalidate()
        #expect(try await waiting.value.setup.hostnames == ["games-jp.test"])
    }

    /// Cancellation ends a status call at once, also while it waits for a restart; the restart
    /// itself continues.
    @Test func aCancelledCallStopsWaitingForTheRestart() async throws {
        let daemon = FakeDaemonService(.enabled)
        daemon.configure { $0.exitingChecks = 1 }
        let gate = PauseGate()
        let (client, _) = RecoveryFixture.client(try RecoveryFixture.configuredHelper(), daemon: daemon, gate: gate)
        let first = Task { try await client.status() }
        await gate.waitUntilPaused()
        let waiting = Task { try await client.status() }
        await RecoveryFixture.settle()
        waiting.cancel()
        let safety = Task {
            try await Task.sleep(for: .seconds(5))
            gate.open()
        }
        let result = await waiting.result
        let endedBeforeTheRestart = !gate.isOpen
        safety.cancel()
        gate.open()
        #expect(endedBeforeTheRestart)
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(try await first.value.setup.hostnames == ["games-jp.test"])
        #expect(daemon.registrations == 1)
    }

    /// Remove System Setup during a restart ends unregistered: the restart cannot register the
    /// helper again after the removal.
    @Test func aRemovalDuringARestartEndsUnregistered() async throws {
        let daemon = FakeDaemonService(.enabled)
        daemon.configure { $0.exitingChecks = 1 }
        let gate = PauseGate()
        let (client, _) = RecoveryFixture.client(try RecoveryFixture.configuredHelper(), daemon: daemon, gate: gate)
        let first = Task { try await client.status() }
        await gate.waitUntilPaused()
        let removal = Task { try await client.unregister() }
        await RecoveryFixture.settle()
        gate.open()
        _ = await first.result
        try await removal.value
        #expect(daemon.calls == ["unregister", "register", "unregister"])
        #expect(daemon.status == .notRegistered)
    }

    /// Two Reconnects during a failing automatic restart run one new registration, not two in parallel.
    @Test func twoReconnectsDuringAFailedRestartRunOneRegistration() async throws {
        let daemon = FakeDaemonService(.enabled)
        let refused = FakeDaemonService.operationNotPermitted
        daemon.configure {
            $0.exitingChecks = 1
            $0.registerErrors = Array(repeating: refused, count: HelperRegistration.registerAttempts)
        }
        let gate = PauseGate()
        let (client, _) = RecoveryFixture.client(try RecoveryFixture.configuredHelper(), daemon: daemon, gate: gate)
        let first = Task { try await client.status() }
        await gate.waitUntilPaused()
        let one = Task { try await client.reconnect() }
        let two = Task { try await client.reconnect() }
        await RecoveryFixture.settle()
        gate.open()
        await #expect(throws: HelperRegistrationFailure.disabledError) { try await first.value }
        try await one.value
        try await two.value
        let attempts = HelperRegistration.registerAttempts
        #expect(daemon.calls == ["unregister"] + Array(repeating: "register", count: attempts + 1))
        #expect(daemon.registrations == 1)
    }

    @Test func quitWaitsForARunningRestartOnlyUpToItsLimit() async throws {
        let daemon = FakeDaemonService(.enabled)
        daemon.configure { $0.exitingChecks = 1 }
        let gate = PauseGate()
        let (client, _) = RecoveryFixture.client(try RecoveryFixture.configuredHelper(), daemon: daemon, gate: gate)
        #expect(await client.finishRunningRestart(within: .milliseconds(10)))
        let first = Task { try await client.status() }
        await gate.waitUntilPaused()
        #expect(await !client.finishRunningRestart(within: .milliseconds(50)))
        let finished = Task { await client.finishRunningRestart(within: .seconds(30)) }
        await RecoveryFixture.settle()
        gate.open()
        #expect(await finished.value)
        #expect(daemon.status == .enabled)
        _ = try await first.value
    }
}

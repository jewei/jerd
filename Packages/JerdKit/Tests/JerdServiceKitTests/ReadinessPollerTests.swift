import JerdFoundation
import JerdServiceKit
import Testing

@Suite struct ReadinessPollerTests {
    private func check(_ probe: ProbeScript, detail: ReadinessCheck.TimeoutDetail = .lastFailure) -> ReadinessCheck {
        ReadinessCheck(
            deadline: .seconds(45), interval: .milliseconds(100), initialFailure: "No response.",
            timeoutMessage: "Timed out.", timeoutDetail: detail, probe: { try await probe.next() })
    }

    @Test func aReadyProbeEndsThePollAfterTheEarlierFailures() async throws {
        let probe = ProbeScript()
        probe.set([.notReady("starting"), .notReady("starting"), .ready])
        let clock = FakeTimeKeeper()
        let outcome = try await ReadinessPoller(clock: clock).poll(check(probe), isAlive: { true })
        #expect(outcome == .ready)
        #expect(probe.calls == 3)
        #expect(clock.sleeps == 2)
    }

    @Test func anExitedProcessEndsThePollBeforeTheNextProbe() async throws {
        let probe = ProbeScript()
        let outcome = try await ReadinessPoller(clock: FakeTimeKeeper()).poll(check(probe), isAlive: { false })
        #expect(outcome == .exited)
        #expect(probe.calls == 0)
    }

    @Test func theDeadlineReportsTheLastFailureWithSecretsRedacted() async throws {
        let probe = ProbeScript()
        probe.always(.notReady("access denied for password hunter2"))
        let clock = FakeTimeKeeper()
        let outcome = try await ReadinessPoller(clock: clock).poll(
            check(probe), secrets: ["hunter2"], isAlive: { true })
        #expect(outcome == .timedOut(lastFailure: "access denied for password [redacted]"))
        #expect(clock.sleeps == 450)
    }

    @Test func aThrownProbeErrorBecomesTheLastFailure() async throws {
        let probe = ProbeScript()
        probe.always(.failure(.timedOut("Command timed out: /bin/client")))
        let outcome = try await ReadinessPoller(clock: FakeTimeKeeper()).poll(check(probe), isAlive: { true })
        #expect(outcome == .timedOut(lastFailure: "Command timed out: /bin/client"))
    }

    @Test func redactionHappensBeforeTheFailureIsShortened() async throws {
        let secret = String(repeating: "s", count: 40)
        let probe = ProbeScript()
        // The secret crosses the 1 024-character cut. No fragment of it may remain.
        probe.always(.notReady(secret + String(repeating: "x", count: 1_000)))
        let outcome = try await ReadinessPoller(clock: FakeTimeKeeper()).poll(
            check(probe), secrets: [secret], isAlive: { true })
        guard case .timedOut(let text) = outcome else {
            Issue.record("Expected a timeout")
            return
        }
        #expect(text.count <= ReadinessPoller.failureLimit)
        #expect(!text.contains("s"))
    }

    @Test func noProbeAnswerKeepsTheInitialFailure() async throws {
        let instant = ReadinessCheck(
            deadline: .zero, interval: .milliseconds(100), initialFailure: "No response.", timeoutMessage: "Timed out.",
            timeoutDetail: .lastFailure, probe: { .ready })
        let outcome = try await ReadinessPoller(clock: FakeTimeKeeper()).poll(instant, isAlive: { true })
        #expect(outcome == .timedOut(lastFailure: "No response."))
    }

    @Test func cancellationStopsThePoll() async throws {
        let probe = ProbeScript()
        probe.always(.notReady("wait"))
        let task = Task {
            try await ReadinessPoller(clock: SystemTimeKeeper()).poll(check(probe), isAlive: { true })
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

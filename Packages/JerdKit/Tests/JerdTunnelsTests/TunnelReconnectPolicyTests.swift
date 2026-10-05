import JerdFoundation
import JerdTunnels
import Testing

@Suite struct TunnelReconnectPolicyTests {
    private let policy = TunnelReconnectPolicy.standard
    private let start = ContinuousClock.now
    private let first = TunnelGeneration(1)

    /// Reduces `events` in order from `lifecycle`, one second apart, and returns every transition.
    private func run(_ events: [TunnelEvent], from lifecycle: TunnelLifecycle = .idle) -> [TunnelTransition] {
        var current = lifecycle
        var transitions: [TunnelTransition] = []
        for (index, event) in events.enumerated() {
            let transition = policy.reduce(current, event, now: start.advanced(by: .seconds(index)))
            transitions.append(transition)
            current = transition.lifecycle
        }
        return transitions
    }

    private func progress(_ value: TunnelProgress) -> TunnelEvent { .progress(first, value) }

    private var launchedEvents: [TunnelEvent] {
        [.connectRequested(first, restartOnFailure: true), progress(.launched)]
    }

    @Test func connectLaunchesAndThenChecksAtOnce() {
        let transitions = run(launchedEvents)
        #expect(transitions[0].lifecycle.state == .starting)
        #expect(transitions[0].step == .launch)
        #expect(transitions[1].step == .check(after: .zero))
    }

    /// Fix of spec E 7.1.18: the first connection showed "Reconnecting…".
    @Test func theFirstConnectionShowsConnectingAndALostOneShowsReconnecting() {
        let transitions = run(
            launchedEvents + [progress(.probed(.waiting)), progress(.probed(.ready)), progress(.probed(.waiting))])
        #expect(transitions[1].lifecycle.state == .connecting)
        #expect(transitions[2].lifecycle.state == .connecting)
        #expect(transitions[3].lifecycle.state == .connected)
        #expect(transitions[3].step == .check(after: .seconds(5)))
        #expect(transitions[4].lifecycle.state == .reconnecting)
    }

    @Test func exitsRetryWithTheBackoffSequenceAndRepeatTheLastDelay() {
        var events = launchedEvents
        for _ in 0..<7 { events += [progress(.probed(.exited)), progress(.reaped(.stopped)), progress(.launched)] }
        let delays = run(events).compactMap { transition -> Duration? in
            if case .relaunch(let delay) = transition.step { return delay }
            return nil
        }
        #expect(delays == [2, 5, 15, 30, 60, 60, 60].map { Duration.seconds($0) })
    }

    @Test func aConnectionThatStaysReadyThirtySecondsResetsTheBackoff() {
        var lifecycle = run(launchedEvents).last?.lifecycle ?? .idle
        lifecycle.retries = 4
        let ready = progress(.probed(.ready))
        let early = policy.reduce(lifecycle, ready, now: start)
        let short = policy.reduce(early.lifecycle, ready, now: start.advanced(by: .seconds(29)))
        #expect(short.lifecycle.retries == 4)
        let stable = policy.reduce(short.lifecycle, ready, now: start.advanced(by: .seconds(30)))
        #expect(stable.lifecycle.retries == 0)
    }

    @Test func aCheckThatIsNotReadyRestartsTheStableClock() {
        var lifecycle = run(launchedEvents).last?.lifecycle ?? .idle
        lifecycle.retries = 3
        let ready = progress(.probed(.ready))
        var current = policy.reduce(lifecycle, ready, now: start).lifecycle
        current = policy.reduce(current, progress(.probed(.waiting)), now: start.advanced(by: .seconds(10))).lifecycle
        current = policy.reduce(current, ready, now: start.advanced(by: .seconds(20))).lifecycle
        current = policy.reduce(current, ready, now: start.advanced(by: .seconds(45))).lifecycle
        #expect(current.retries == 3)
    }

    @Test func anExitWithoutRestartNeedsTheUser() {
        let events: [TunnelEvent] = [
            .connectRequested(first, restartOnFailure: false), progress(.launched), progress(.probed(.exited)),
            progress(.reaped(.stopped)),
        ]
        let last = run(events).last
        #expect(last?.lifecycle.state == .failed(TunnelMessage.processExited))
        #expect(last?.lifecycle.generation == nil)
        #expect(last?.step == .idle)
    }

    @Test func aRejectedTokenStopsTheConnectorAndNeverRetries() {
        let transitions = run(launchedEvents + [progress(.probed(.tokenRejected))])
        #expect(transitions[2].step == .disconnect(.tokenRejected))
        #expect(transitions[2].lifecycle.state == .failed(TunnelMessage.tokenRejected))
        let done = run([progress(.disconnected(.tokenRejected, stopError: nil))], from: transitions[2].lifecycle)
        #expect(done[0].lifecycle.state == .failed(TunnelMessage.tokenRejected))
        #expect(done[0].lifecycle.generation == nil)
        let stuck = run(
            [progress(.disconnected(.tokenRejected, stopError: "Timed out."))], from: transitions[2].lifecycle)
        #expect(stuck[0].lifecycle.state == .failed("Cloudflare rejected the token. Timed out."))
    }

    @Test func aLateRejectionInTheOutputOfAnExitedConnectorStopsRetries() {
        let last = run(launchedEvents + [progress(.probed(.exited)), progress(.reaped(.stoppedAfterTokenRejection))])
        #expect(last.last?.lifecycle.state == .failed(TunnelMessage.tokenRejected))
        #expect(last.last?.step == .idle)
    }

    @Test func anUnexpectedListenerStopsTheConnectorAndKeepsItsMessage() {
        let transitions = run(
            launchedEvents + [
                progress(.probed(.unexpectedListener)),
                progress(.disconnected(.unexpectedListener, stopError: "Timed out.")),
            ])
        #expect(transitions[2].step == .disconnect(.unexpectedListener))
        #expect(transitions[3].lifecycle.state == .failed(TunnelMessage.unexpectedListener))
        #expect(transitions[3].lifecycle.generation == nil)
    }

    @Test func aGroupThatCannotBeCollectedNeedsTheUser() {
        let last = run(launchedEvents + [progress(.probed(.exited)), progress(.reaped(.notStopped("Still running.")))])
        #expect(last.last?.lifecycle.state == .failed("Still running."))
    }

    @Test func everyFirstLaunchFailureNeedsTheUser() {
        for error in [JerdError.timedOut("Timed out."), .unavailable("Port busy.")] {
            let events: [TunnelEvent] = [
                .connectRequested(first, restartOnFailure: true), progress(.launchFailed(TunnelFailure(error))),
            ]
            let last = run(events).last
            #expect(last?.lifecycle.state == .failed(error.message))
            #expect(last?.step == .idle)
        }
    }

    /// Fix of spec E 7.1.2: a retry that hit a permanent error showed "Reconnecting…" forever.
    @Test func aRetryRetriesOnlyTransientFailures() {
        let retrying = run(launchedEvents + [progress(.probed(.exited)), progress(.reaped(.stopped))]).last?.lifecycle
        let permanent: [JerdError] = [
            .unavailable(TunnelMessage.tokenMissing), .invalid(TunnelMessage.tokenFormat),
            .unavailable(TunnelMessage.versionMismatch), .locked(TunnelMessage.lockBusy),
            .unavailable("Local port 20241 is occupied. No process was stopped."), .corrupt("Bad record."),
        ]
        for error in permanent {
            let last = run([progress(.launchFailed(TunnelFailure(error)))], from: retrying ?? .idle)
            #expect(last[0].lifecycle.state == .failed(error.message))
            #expect(last[0].step == .idle)
        }
        for error in [JerdError.timedOut("Slow."), .processFailed(TunnelMessage.exitedEarly)] {
            let last = run([progress(.launchFailed(TunnelFailure(error)))], from: retrying ?? .idle)
            #expect(last[0].step == .relaunch(after: .seconds(5)))
            #expect(last[0].lifecycle.state == .connecting)
        }
    }

    @Test func resultsOfAnOlderGenerationChangeNothing() {
        let current = run([.connectRequested(TunnelGeneration(2), restartOnFailure: true)])[0].lifecycle
        for stale in [TunnelProgress.launched, .probed(.unexpectedListener), .probed(.exited), .reaped(.stopped)] {
            let transition = policy.reduce(current, .progress(first, stale), now: start)
            #expect(transition.lifecycle == current)
            #expect(transition.step == .idle)
        }
    }

    @Test func stopEndsTheGenerationAndItsResult() {
        let stopping = run(launchedEvents + [.stopRequested]).last
        #expect(stopping?.lifecycle.state == .stopping)
        #expect(stopping?.lifecycle.generation == nil)
        #expect(run([.stopFinished(error: nil)]).last?.lifecycle.state == .stopped)
        #expect(run([.stopFinished(error: "Still running.")]).last?.lifecycle.state == .failed("Still running."))
        let late = run([progress(.launched)], from: stopping?.lifecycle ?? .idle)
        #expect(late[0].lifecycle.state == .stopping)
    }

    @Test func cancellationAndUnknownErrorsBecomeTunnelFailures() {
        #expect(TunnelFailure(CancellationError()).message == TunnelMessage.cancelled)
        #expect(!TunnelFailure(CancellationError()).isTransient)
        #expect(TunnelFailure(SampleError()).error.kind == .processFailed)
    }

    @Test func anEmptyDelayListWaitsSixtySeconds() {
        #expect(TunnelReconnectPolicy(retryDelays: []).retryDelays == [.seconds(60)])
        #expect(policy.retryDelay(after: 99) == .seconds(60))
    }
}

private struct SampleError: Error {}

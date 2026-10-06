import Darwin
import Testing

@testable import JerdProcess

@Suite struct StopEngineTests {
    private let forceful = StopPolicy.forceful(leaderTimeout: .zero, groupTimeout: .zero, killWait: .zero)
    private let graceful = StopPolicy.graceful(timeout: .zero)

    @Test func aTargetThatIsNotOwnedGetsNoSignal() async {
        let target = FakeStopTarget(state: .notOwned)
        #expect(await StopEngine.run(forceful, on: target) == .notOwned)
        #expect(target.signals.isEmpty)
    }

    @Test func anAlreadyExitedLeaderWithAnEmptyGroupIsStoppedWithoutAnySignal() async {
        let target = FakeStopTarget(state: .exited(status: 0))
        #expect(await StopEngine.run(graceful, on: target) == .stopped)
        #expect(target.signals.isEmpty)
    }

    @Test func aLeaderThatObeysTheFirstSignalGetsNoGroupSignal() async {
        let target = FakeStopTarget(state: .running, leaderExitsOn: [SIGQUIT])
        #expect(await StopEngine.run(.forceful(signal: SIGQUIT), on: target) == .stopped)
        #expect(target.signals == [.leader(SIGQUIT), .group(SIGCONT)])
    }

    @Test func aGracefulTimeoutKeepsTheLeaderAndNeverKills() async {
        let target = FakeStopTarget(state: .running)
        #expect(await StopEngine.run(graceful, on: target) == .timedOut(leaderRunning: true))
        #expect(target.signals == [.leader(SIGTERM), .group(SIGCONT)])
    }

    @Test func gracefulStopSignalsRemainingMembersOnceAndNeverKills() async {
        let stubborn = FakeStopTarget(state: .running, leaderExitsOn: [SIGINT], membersRemain: true)
        #expect(
            await StopEngine.run(.graceful(signal: SIGINT, timeout: .zero), on: stubborn)
                == .timedOut(leaderRunning: false))
        #expect(stubborn.signals == [.leader(SIGINT), .group(SIGCONT), .group(SIGTERM), .group(SIGCONT)])
        let obedient = FakeStopTarget(
            state: .running, leaderExitsOn: [SIGTERM], membersRemain: true, membersExitOn: [SIGTERM])
        #expect(await StopEngine.run(graceful, on: obedient) == .stopped)
        #expect(obedient.signals == [.leader(SIGTERM), .group(SIGCONT), .group(SIGTERM), .group(SIGCONT)])
    }

    @Test func forcefulStopEscalatesToAGroupKill() async {
        let target = FakeStopTarget(state: .running, leaderExitsOn: [SIGKILL])
        #expect(await StopEngine.run(forceful, on: target) == .stopped)
        #expect(
            target.signals == [.leader(SIGTERM), .group(SIGCONT), .group(SIGTERM), .group(SIGCONT), .group(SIGKILL)])
    }

    @Test func aLeaderThatSurvivesTheKillTimesOutInsteadOfWaitingForever() async {
        let target = FakeStopTarget(state: .running)
        #expect(await StopEngine.run(forceful, on: target) == .timedOut(leaderRunning: true))
        #expect(
            target.signals == [.leader(SIGTERM), .group(SIGCONT), .group(SIGTERM), .group(SIGCONT), .group(SIGKILL)])
    }

    @Test func policiesHaveTheDocumentedTimings() {
        #expect(
            StopPolicy.forceful()
                == StopPolicy(
                    signal: SIGTERM, leaderTimeout: .seconds(3), groupTimeout: .seconds(2),
                    escalation: .kill(wait: .seconds(2))))
        #expect(
            StopPolicy.graceful()
                == StopPolicy(
                    signal: SIGTERM, leaderTimeout: .seconds(30), groupTimeout: nil, escalation: .never))
    }

    /// Regression test: a leader that something else reaps during the stop gets no group signal.
    @Test func aLeaderReapedOutsideDuringTheStopGetsNoFurtherSignal() async {
        let target = FakeStopTarget(state: .running, reapedOutsideOn: SIGTERM)
        #expect(await StopEngine.run(forceful, on: target) == .notOwned)
        #expect(target.signals == [.leader(SIGTERM)])
        let reapedAfterGroupSignal = FakeStopTarget(
            state: .running, leaderExitsOn: [SIGTERM], membersRemain: true, reapedOutsideOn: SIGTERM)
        #expect(await StopEngine.run(forceful, on: reapedAfterGroupSignal) == .notOwned)
    }

    /// Regression test: after the group kill the engine waits for an empty group, not only for the leader.
    @Test func membersThatSurviveTheKillTimeOutInsteadOfReportingStopped() async {
        let target = FakeStopTarget(state: .running, leaderExitsOn: [SIGTERM], membersRemain: true)
        #expect(await StopEngine.run(forceful, on: target) == .timedOut(leaderRunning: false))
        #expect(
            target.signals == [.leader(SIGTERM), .group(SIGCONT), .group(SIGTERM), .group(SIGCONT), .group(SIGKILL)])
    }

    /// Regression test: descendants are recorded while the leader still runs, before any signal.
    @Test func descendantsAreRecordedBeforeTheFirstSignal() async {
        let target = FakeStopTarget(state: .running, leaderExitsOn: [SIGTERM])
        #expect(await StopEngine.run(graceful, on: target) == .stopped)
        #expect(target.events == [.walk, .signal(.leader(SIGTERM)), .signal(.group(SIGCONT))])
    }

    /// Regression test: a graceful ceiling removes the kill step of any policy and keeps the rest.
    @Test func aGracefulCeilingNeverKills() async {
        let limited = StopCeiling.graceful.limit(.forceful(signal: SIGQUIT))
        #expect(
            limited
                == StopPolicy(
                    signal: SIGQUIT, leaderTimeout: .seconds(3), groupTimeout: .seconds(2), escalation: .never))
        #expect(StopCeiling.forceful.limit(.forceful()) == .forceful())
        #expect(StopCeiling.graceful.limit(.graceful()) == .graceful())
        let target = FakeStopTarget(state: .running)
        #expect(
            await StopEngine.run(StopCeiling.graceful.limit(forceful), on: target) == .timedOut(leaderRunning: true))
        #expect(!target.signals.contains(.group(SIGKILL)))
    }
}

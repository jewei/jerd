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
        #expect(target.signals == [.leader(SIGQUIT)])
    }

    @Test func aGracefulTimeoutKeepsTheLeaderAndNeverKills() async {
        let target = FakeStopTarget(state: .running)
        #expect(await StopEngine.run(graceful, on: target) == .timedOut(leaderRunning: true))
        #expect(target.signals == [.leader(SIGTERM)])
    }

    @Test func gracefulStopSignalsRemainingMembersOnceAndNeverKills() async {
        let stubborn = FakeStopTarget(state: .running, leaderExitsOn: [SIGINT], membersRemain: true)
        #expect(
            await StopEngine.run(.graceful(signal: SIGINT, timeout: .zero), on: stubborn)
                == .timedOut(leaderRunning: false))
        #expect(stubborn.signals == [.leader(SIGINT), .group(SIGTERM)])
        let obedient = FakeStopTarget(
            state: .running, leaderExitsOn: [SIGTERM], membersRemain: true, membersExitOn: [SIGTERM])
        #expect(await StopEngine.run(graceful, on: obedient) == .stopped)
        #expect(obedient.signals == [.leader(SIGTERM), .group(SIGTERM)])
    }

    @Test func forcefulStopEscalatesToAGroupKill() async {
        let target = FakeStopTarget(state: .running, leaderExitsOn: [SIGKILL])
        #expect(await StopEngine.run(forceful, on: target) == .stopped)
        #expect(target.signals == [.leader(SIGTERM), .group(SIGTERM), .group(SIGKILL)])
    }

    @Test func aLeaderThatSurvivesTheKillTimesOutInsteadOfWaitingForever() async {
        let target = FakeStopTarget(state: .running)
        #expect(await StopEngine.run(forceful, on: target) == .timedOut(leaderRunning: true))
        #expect(target.signals == [.leader(SIGTERM), .group(SIGTERM), .group(SIGKILL)])
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
}

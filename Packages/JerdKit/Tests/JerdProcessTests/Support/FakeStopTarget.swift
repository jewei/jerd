import Darwin
import os

@testable import JerdProcess

/// A scripted process group for stop engine tests. It records every signal in order.
final class FakeStopTarget: StopTarget {
    /// One recorded signal.
    enum Signal: Equatable {
        case leader(Int32)
        case group(Int32)
    }

    private struct Script {
        var state: ProcessState
        /// Signals after which the leader exits.
        var leaderExitsOn: Set<Int32>
        /// Signals after which the other members exit.
        var membersExitOn: Set<Int32>
        var membersRemain: Bool
        var signals: [Signal] = []
    }

    private let script: OSAllocatedUnfairLock<Script>

    init(
        state: ProcessState, leaderExitsOn: Set<Int32> = [], membersRemain: Bool = false, membersExitOn: Set<Int32> = []
    ) {
        script = OSAllocatedUnfairLock(
            initialState: Script(
                state: state, leaderExitsOn: leaderExitsOn, membersExitOn: membersExitOn, membersRemain: membersRemain))
    }

    var signals: [Signal] { script.withLock { $0.signals } }

    func leaderState() -> ProcessState { script.withLock { $0.state } }

    func signalLeader(_ signal: Int32) {
        script.withLock { script in
            script.signals.append(.leader(signal))
            if script.leaderExitsOn.contains(signal) { script.state = .signalled(signal: signal) }
        }
    }

    func signalGroup(_ signal: Int32) {
        script.withLock { script in
            script.signals.append(.group(signal))
            if script.leaderExitsOn.contains(signal), script.state == .running {
                script.state = .signalled(signal: signal)
            }
            if script.membersExitOn.contains(signal) { script.membersRemain = false }
        }
    }

    func waitForLeaderExit(until deadline: ContinuousClock.Instant) async -> Bool {
        leaderState() != .running
    }

    func waitForEmptyGroup(until deadline: ContinuousClock.Instant) async -> Bool {
        leaderState() != .running && !mayHaveOtherMembers()
    }

    func mayHaveOtherMembers() -> Bool { script.withLock { $0.membersRemain } }
}

import Darwin
import os

@testable import JerdProcess

/// A scripted process group for stop engine tests. It records every signal and walk in order.
final class FakeStopTarget: StopTarget {
    /// One recorded signal.
    enum Signal: Equatable {
        case leader(Int32)
        case group(Int32)
    }

    /// One recorded call: a signal or a descendant walk.
    enum Event: Equatable {
        case signal(Signal)
        case walk
    }

    private struct Script {
        var state: ProcessState
        /// Signals after which the leader exits.
        var leaderExitsOn: Set<Int32>
        /// Signals after which the other members exit.
        var membersExitOn: Set<Int32>
        var membersRemain: Bool
        /// A signal after which something outside the supervisor reaps the leader.
        var reapedOutsideOn: Int32?
        var events: [Event] = []
    }

    private let script: OSAllocatedUnfairLock<Script>

    init(
        state: ProcessState, leaderExitsOn: Set<Int32> = [], membersRemain: Bool = false,
        membersExitOn: Set<Int32> = [], reapedOutsideOn: Int32? = nil
    ) {
        script = OSAllocatedUnfairLock(
            initialState: Script(
                state: state, leaderExitsOn: leaderExitsOn, membersExitOn: membersExitOn, membersRemain: membersRemain,
                reapedOutsideOn: reapedOutsideOn))
    }

    var events: [Event] { script.withLock { $0.events } }

    var signals: [Signal] {
        events.compactMap { event in
            if case .signal(let signal) = event { return signal }
            return nil
        }
    }

    func leaderState() -> ProcessState { script.withLock { $0.state } }

    func trackDescendants() -> Bool {
        script.withLock { $0.events.append(.walk) }
        return true
    }

    func signalLeader(_ signal: Int32) {
        script.withLock { script in
            script.events.append(.signal(.leader(signal)))
            if script.leaderExitsOn.contains(signal) { script.state = .signalled(signal: signal) }
            if script.reapedOutsideOn == signal { script.state = .notOwned }
        }
    }

    func signalGroup(_ signal: Int32) {
        script.withLock { script in
            script.events.append(.signal(.group(signal)))
            if script.leaderExitsOn.contains(signal), script.state == .running {
                script.state = .signalled(signal: signal)
            }
            if script.membersExitOn.contains(signal) { script.membersRemain = false }
            if script.reapedOutsideOn == signal { script.state = .notOwned }
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

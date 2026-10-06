import Darwin

/// Runs a `StopPolicy` on one process group. Both stop strategies use this one sequence.
///
/// 1. A target that is not owned gets no signal: `.notOwned`.
/// 2. A running leader: the descendants are recorded, then the leader gets `policy.signal`.
/// 3. If the leader exited and no other member remains: `.stopped`.
/// 4. A leader that still runs under a never-kill policy: `.timedOut(leaderRunning: true)`.
/// 5. Otherwise the group gets `SIGTERM` and the engine waits for an empty group.
/// 6. Never-kill policy: `.timedOut`. Kill policy: group `SIGKILL` and a bounded wait for an
///    empty group.
///
/// Ownership is read again after every wait: a leader that something else reaped during the stop
/// gives `.notOwned` at once, with no further signal, because its group ID is no longer reserved.
enum StopEngine {
    static func run(_ policy: StopPolicy, on target: some StopTarget) async -> StopOutcome {
        let state = target.leaderState()
        guard state != .notOwned else { return .notOwned }
        if state.isRunning {
            target.trackDescendants()
            target.signalLeader(policy.signal)
        }
        let leaderDeadline = ContinuousClock.now + policy.leaderTimeout
        let leaderExited = await target.waitForLeaderExit(until: leaderDeadline)
        guard target.leaderState() != .notOwned else { return .notOwned }
        if leaderExited, !target.mayHaveOtherMembers() { return .stopped }
        if !leaderExited, policy.escalation == .never { return .timedOut(leaderRunning: true) }
        target.signalGroup(SIGTERM)
        let groupDeadline = policy.groupTimeout.map { ContinuousClock.now + $0 } ?? leaderDeadline
        let emptied = await target.waitForEmptyGroup(until: groupDeadline)
        guard target.leaderState() != .notOwned else { return .notOwned }
        if emptied { return .stopped }
        guard case .kill(let wait) = policy.escalation else { return timedOut(target) }
        target.signalGroup(SIGKILL)
        let killed = await target.waitForEmptyGroup(until: ContinuousClock.now + wait)
        guard target.leaderState() != .notOwned else { return .notOwned }
        return killed ? .stopped : timedOut(target)
    }

    private static func timedOut(_ target: some StopTarget) -> StopOutcome {
        .timedOut(leaderRunning: target.leaderState().isRunning)
    }
}

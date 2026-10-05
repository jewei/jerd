import Darwin

/// Runs a `StopPolicy` on one process group. Both stop strategies use this one sequence.
///
/// 1. A target that is not owned gets no signal: `.notOwned`.
/// 2. A running leader gets `policy.signal`; the engine waits for its exit.
/// 3. If the leader exited and no other member remains: `.stopped`.
/// 4. A leader that still runs under a never-kill policy: `.timedOut(leaderRunning: true)`.
/// 5. Otherwise the group gets `SIGTERM` and the engine waits for an empty group.
/// 6. Never-kill policy: `.timedOut`. Kill policy: group `SIGKILL` and a bounded wait for the leader.
enum StopEngine {
    static func run(_ policy: StopPolicy, on target: some StopTarget) async -> StopOutcome {
        let state = target.leaderState()
        guard state != .notOwned else { return .notOwned }
        if state.isRunning { target.signalLeader(policy.signal) }
        let leaderDeadline = ContinuousClock.now + policy.leaderTimeout
        let leaderExited = await target.waitForLeaderExit(until: leaderDeadline)
        if leaderExited, !target.mayHaveOtherMembers() { return .stopped }
        if !leaderExited, policy.escalation == .never { return .timedOut(leaderRunning: true) }
        target.signalGroup(SIGTERM)
        let groupDeadline = policy.groupTimeout.map { ContinuousClock.now + $0 } ?? leaderDeadline
        if await target.waitForEmptyGroup(until: groupDeadline) { return .stopped }
        guard case .kill(let wait) = policy.escalation else {
            return .timedOut(leaderRunning: target.leaderState().isRunning)
        }
        target.signalGroup(SIGKILL)
        let killed = await target.waitForLeaderExit(until: ContinuousClock.now + wait)
        return killed ? .stopped : .timedOut(leaderRunning: true)
    }
}

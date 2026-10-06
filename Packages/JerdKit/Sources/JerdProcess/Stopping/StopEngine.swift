import Darwin

/// Runs a `StopPolicy` on one process group. Both stop strategies use this one sequence.
///
/// 1. A target that is not owned gets no signal: `.notOwned`.
/// 2. A running leader: the descendants are recorded, then the leader gets `policy.signal`, and the
///    group gets `SIGCONT`.
/// 3. If the leader exited and no other member remains: `.stopped`.
/// 4. A leader that still runs under a never-kill policy: `.timedOut(leaderRunning: true)`.
/// 5. Otherwise the group gets `SIGTERM`, then `SIGCONT`, and the engine waits for an empty group.
/// 6. Never-kill policy: `.timedOut`. Kill policy: group `SIGKILL` and a bounded wait for an
///    empty group.
///
/// A policy without signals (`StopPolicy.completeExited`) stops after step 3: it gives
/// `.stopped` for an exited leader with an empty group, and `.timedOut` otherwise.
///
/// `SIGCONT` follows each stop signal because a paused process (`SIGSTOP`, a debugger, a job-control
/// stop) keeps a caught signal pending until it continues. Without it, a paused data service could
/// never shut down gracefully. `SIGKILL` needs no `SIGCONT`: it also ends a paused process.
///
/// Ownership is read again after every wait: a leader that something else reaped during the stop
/// gives `.notOwned` at once, with no further signal, because its group ID is no longer reserved.
enum StopEngine {
    static func run(_ policy: StopPolicy, on target: some StopTarget) async -> StopOutcome {
        let state = target.leaderState()
        guard state != .notOwned else { return .notOwned }
        if state.isRunning {
            guard policy.sendsSignals else { return .timedOut(leaderRunning: true) }
            target.trackDescendants()
            target.signalLeader(policy.signal)
            resume(target)
        }
        let leaderDeadline = ContinuousClock.now + policy.leaderTimeout
        let leaderExited = await target.waitForLeaderExit(until: leaderDeadline)
        guard target.leaderState() != .notOwned else { return .notOwned }
        if leaderExited, !target.mayHaveOtherMembers() { return .stopped }
        guard policy.sendsSignals else { return timedOut(target) }
        if !leaderExited, policy.escalation == .never { return .timedOut(leaderRunning: true) }
        target.signalGroup(SIGTERM)
        resume(target)
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

    /// Continues a paused group so that it can act on the stop signal. A leader that something
    /// else reaped gets nothing: its group ID is no longer reserved.
    private static func resume(_ target: some StopTarget) {
        guard target.leaderState() != .notOwned else { return }
        target.signalGroup(SIGCONT)
    }

    private static func timedOut(_ target: some StopTarget) -> StopOutcome {
        .timedOut(leaderRunning: target.leaderState().isRunning)
    }
}

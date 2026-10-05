import Darwin

/// The live stop target: an own, unreaped group leader and its process group.
///
/// The leader stays unreaped during the whole stop, so its PID and group ID cannot be reused
/// and every group signal reaches only processes that Jerd started.
struct SupervisedGroup: StopTarget {
    let leader: pid_t
    let inspector: ProcessGroupInspector
    /// How often group membership is read while waiting. Leader exits need no polling.
    let pollInterval: Duration

    func leaderState() -> ProcessState { ChildStatus.peek(leader) }

    func signalLeader(_ signal: Int32) { _ = kill(leader, signal) }

    func signalGroup(_ signal: Int32) { _ = kill(-leader, signal) }

    func waitForLeaderExit(until deadline: ContinuousClock.Instant) async -> Bool {
        await ExitWatcher.wait(for: leader, until: deadline) != .running
    }

    func waitForEmptyGroup(until deadline: ContinuousClock.Instant) async -> Bool {
        guard await waitForLeaderExit(until: deadline) else { return false }
        while mayHaveOtherMembers() {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: min(pollInterval, deadline - ContinuousClock.now))
        }
        return true
    }

    func mayHaveOtherMembers() -> Bool {
        inspector.mayHaveMembers(otherThan: leader, in: leader)
    }
}

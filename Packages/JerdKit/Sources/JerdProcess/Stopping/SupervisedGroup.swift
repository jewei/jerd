import Darwin

/// The live stop target: an own, unreaped group leader, its process group, and the descendants
/// that left the group.
///
/// The leader stays unreaped during the whole stop, so its PID and group ID cannot be reused
/// and every group signal reaches only processes that Jerd started. A descendant that called
/// `setsid` or `setpgid` is found by its parent chain while its parent runs. It then gets each
/// group signal by PID, checked against its start time just before the signal, and it blocks
/// `.stopped` until it exits.
struct SupervisedGroup: StopTarget {
    let leader: pid_t
    let inspector: ProcessGroupInspector
    let tree: ProcessTree
    let descendants: TrackedDescendants
    /// How often group membership is read while waiting. Leader exits need no polling.
    let pollInterval: Duration

    func leaderState() -> ProcessState { ChildStatus.peek(leader) }

    func signalLeader(_ signal: Int32) { _ = kill(leader, signal) }

    func signalGroup(_ signal: Int32) {
        _ = kill(-leader, signal)
        for member in descendants.all {
            // A member that is still in the group already got the group signal.
            guard case .live(let now) = tree.current(member), now.groupID != leader else { continue }
            _ = kill(member.processID, signal)
        }
    }

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

    /// Walks the parent chain from the leader, the group members, and the tracked descendants.
    @discardableResult
    func trackDescendants() -> Bool {
        var roots = leaderState().isRunning ? [leader] : []
        if case .members(let pids) = inspector.members(of: leader) { roots += pids }
        roots += descendants.all.map(\.processID)
        guard let found = tree.descendants(of: roots) else { return false }
        descendants.track(found)
        return true
    }

    /// A failed walk counts as "members may remain".
    func mayHaveOtherMembers() -> Bool {
        let walked = trackDescendants()
        let remaining = descendants.refresh(using: tree)
        return !walked || !remaining.isEmpty || inspector.mayHaveMembers(otherThan: leader, in: leader)
    }
}

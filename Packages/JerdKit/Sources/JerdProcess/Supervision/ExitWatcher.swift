import Darwin

/// Waits for an own child to exit, with a deadline, without polling while the child runs.
enum ExitWatcher {
    /// How often the state is read in the short moment between the kernel exit event and the
    /// point where `waitid` reports the exit.
    static let settleInterval: Duration = .milliseconds(1)

    /// Waits until child `pid` is no longer running, the deadline passes, or the task is cancelled.
    /// - Returns: the state after the wait (`.running` at the deadline or on cancellation).
    static func wait(for pid: pid_t, until deadline: ContinuousClock.Instant) async -> ProcessState {
        let event = ExitEvent(pid: pid)
        guard ChildStatus.peek(pid) == .running else { return ChildStatus.peek(pid) }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await event.wait() }
            group.addTask { try? await Task.sleep(until: deadline, clock: .continuous) }
            await group.next()
            group.cancelAll()
        }
        var state = ChildStatus.peek(pid)
        while state == .running, event.exitSeen, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: settleInterval)
            state = ChildStatus.peek(pid)
        }
        return state
    }
}

extension ManagedInstance {
    /// Detects an unexpected exit of a running server and returns the current state.
    ///
    /// It never waits for the stop of the exited group: the stop runs in its own task, the state
    /// is `stopping` meanwhile, and a user Stop joins it. The result is `failed` with the end of
    /// the log, or `stuck` when a group member does not stop in time.
    @discardableResult
    public func refresh() async -> ServiceState {
        guard case .running = state, lease == nil, pendingStop == nil, let owned = process else { return state }
        guard !(await owned.isAlive()) else { return state }
        // The state can change while the check waits. Act only on the same running process.
        guard case .running = state, lease == nil, pendingStop == nil, process?.token == owned.token else {
            return state
        }
        let reason = "\(messages.exited) \(logTail(owned))"
        apply(.stopRequested(pid: owned.processID))
        _ = beginStop(owned, keepLock: false, intent: .exit(reason: reason))
        return state
    }
}

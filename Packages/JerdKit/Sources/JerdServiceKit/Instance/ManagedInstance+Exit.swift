import JerdFoundation

extension ManagedInstance {
    /// Detects an unexpected exit of a running server and returns the current state.
    ///
    /// It never waits for the stop of the exited group: the stop runs in its own task, the state
    /// is `stopping` meanwhile, and a user Stop joins it. The result is `failed` with the end of
    /// the log, or `stuck` when a group member does not stop in time.
    ///
    /// Without an owned process, it shows a saved process of an earlier run (see
    /// `showPreviousProcess()`).
    @discardableResult
    public func refresh() async -> ServiceState {
        guard let owned = process else {
            showPreviousProcess()
            return state
        }
        guard case .running = state, lease == nil, pendingStop == nil else { return state }
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

    /// After a crash or a force quit, the earlier server can still run and serve the data. Then
    /// the state is `failed` with the recovery message, not `stopped` (review final-domain-r1
    /// M1). The check reads the run record only. Another failure text stays, and the message
    /// clears when recovery removed the process.
    private func showPreviousProcess() {
        guard process == nil, lease == nil, !state.isBusy else { return }
        guard state == .stopped || (previousProcessReason != nil && state.failure == previousProcessReason) else {
            previousProcessReason = nil
            return
        }
        do {
            try effects.startGate.requireNoLiveRecord(definition.profile.record)
            if previousProcessReason != nil { apply(.cleared) }
            previousProcessReason = nil
        } catch {
            let reason = FailureDetail.describe(error)
            previousProcessReason = reason
            apply(.operationFailed(reason: reason))
        }
    }
}

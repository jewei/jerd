import JerdFoundation

extension ManagedInstance {
    /// Detects an unexpected exit of a running server and returns the current state.
    ///
    /// It never waits for the stop of the exited group: the stop runs in its own task, the state
    /// is `stopping` meanwhile, and a user Stop joins it. The result is `failed` with the end of
    /// the log, or `stuck` when a group member does not stop in time.
    ///
    /// A `stuck` process that ended later is collected without a signal (see
    /// `completeEndedStuckProcess(_:)`). Without an owned process, it shows a saved process of an
    /// earlier run (see `showPreviousProcess()`).
    @discardableResult
    public func refresh() async -> ServiceState {
        guard let owned = process else {
            showPreviousProcess()
            return state
        }
        if case .stuck = state { return await completeEndedStuckProcess(owned) }
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

    /// A kept process can end later, for example a paused server that a user continues after the
    /// stop timed out. Then the stop completes as a successful Stop does: the record goes, the
    /// lock is free, and the state is `stopped`.
    ///
    /// No process gets a signal (`StopPolicy.completeExited`). While a group member still runs,
    /// the state stays `stuck` with its reason. A leader that something else reaped is checked
    /// against the run record by the start gate, as after every stop.
    private func completeEndedStuckProcess(_ owned: OwnedServiceProcess) async -> ServiceState {
        guard case .stuck = state, lease == nil, pendingStop == nil else { return state }
        guard !(await owned.isAlive()) else { return state }
        // The state can change while the check waits. Act only on the same kept process.
        guard case .stuck(_, let reason) = state, lease == nil, pendingStop == nil, process?.token == owned.token
        else { return state }
        apply(.stopRequested(pid: owned.processID))
        _ = await beginStop(owned, keepLock: false, intent: .completeExit(reason: reason), policy: .completeExited)
            .value
        return state
    }

    /// After a crash or a force quit, the earlier server can still run and serve the data. Then
    /// the state is `failed` with the recovery message, not `stopped`.
    /// The check reads the run record only. Another failure text stays, and the message
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

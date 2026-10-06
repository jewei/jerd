import Darwin
import JerdFoundation
import JerdProcess

extension ManagedInstance {
    /// Stops the owned process gracefully. Valid in every state except `starting`.
    ///
    /// A stop that exit detection began is joined, not refused. Without a process, Stop clears a
    /// failure and releases the lock.
    /// - Throws: `.processFailed` when the stop timed out (state `stuck`) or the saved process
    ///   needs inspection (state `failed`).
    public func stop() async throws {
        try requireNoLease()
        guard state != .starting else { throw JerdError.unavailable(messages.busy) }
        guard let owned = process else {
            releaseLockIfIdle()
            apply(.cleared)
            return
        }
        apply(.stopRequested(pid: owned.processID))
        let result = await stopOwned(owned, keepLock: false, intent: .user)
        if let message = result.failureMessage { throw JerdError.processFailed(message) }
    }

    /// Stops `owned`, or joins the stop of it that is in progress. A user intent replaces an exit
    /// intent, so the user sees `stopped` after a joined exit stop.
    func stopOwned(_ owned: OwnedServiceProcess, keepLock: Bool, intent: StopIntent) async -> StopResult {
        await beginStop(owned, keepLock: keepLock, intent: intent).value
    }

    func beginStop(_ owned: OwnedServiceProcess, keepLock: Bool, intent: StopIntent) -> Task<StopResult, Never> {
        if let pendingStop, pendingStop.token == owned.token {
            if case .user = intent { stopIntent = .user }
            return pendingStop.task
        }
        stopIntent = intent
        let policy = effects.stopPolicy(signal: definition.profile.stopSignal)
        let task = Task {
            let outcome = await owned.stop(policy: policy)
            return self.completeStop(owned, outcome: outcome, keepLock: keepLock)
        }
        pendingStop = PendingStop(token: owned.token, task: task)
        return task
    }

    /// Settles ownership after a stop and applies the state for the intent.
    private func completeStop(_ owned: OwnedServiceProcess, outcome: StopOutcome, keepLock: Bool) -> StopResult {
        pendingStop = nil
        let result: StopResult
        switch outcome {
        case .stopped:
            result = releaseStopped(owned, keepLock: keepLock)
        case .timedOut:
            let profile = definition.profile
            result = .timedOut(ServiceMessages.stopTimedOut(name: profile.name, timeout: effects.stopTimeout))
        case .notOwned:
            result = releaseUnowned(owned, keepLock: keepLock)
        }
        applyStopIntent(result, pid: owned.processID)
        return result
    }

    /// Forgets the stopped process, ends its launch (temporary items and `didStop`), removes its
    /// record, and releases the lock unless the caller keeps it.
    private func releaseStopped(_ owned: OwnedServiceProcess, keepLock: Bool) -> StopResult {
        guard process?.token == owned.token else { return .stopped }
        process = nil
        owned.plan.end()
        if let lock {
            // A record that cannot be removed is stale now. The start gate removes it later
            // under the lock, so a failure here is not a safety problem.
            try? ActiveRunRecordFile.remove(definition.profile.record, holding: lock)
        }
        if !keepLock { releaseLockIfIdle() }
        return .stopped
    }

    /// The child was reaped outside the supervisor. The start gate decides from the record: a
    /// stale record is removed; a live group keeps the record and releases the lock for recovery.
    private func releaseUnowned(_ owned: OwnedServiceProcess, keepLock: Bool) -> StopResult {
        guard process?.token == owned.token else { return .stopped }
        process = nil
        owned.plan.end()
        guard let lock else { return .stopped }
        do {
            _ = try effects.startGate.requireStopped(definition.profile.record, holding: lock)
            if !keepLock { releaseLockIfIdle() }
            return .stopped
        } catch {
            lock.release()
            self.lock = nil
            return .refused("\(ServiceMessages.reapedOutside) \(FailureDetail.describe(error))")
        }
    }

    private func applyStopIntent(_ result: StopResult, pid: pid_t) {
        let intent = stopIntent
        stopIntent = .startStep
        switch (intent, result) {
        case (.startStep, _):
            return
        case (.user, .stopped):
            apply(.stopSucceeded)
        case (.exit(let reason), .stopped):
            apply(.exitReaped(reason: reason))
        case (.user, .timedOut(let message)):
            apply(.stopTimedOut(pid: pid, reason: message))
        case (.exit(let reason), .timedOut):
            apply(.stopTimedOut(pid: pid, reason: "\(reason) \(ServiceMessages.childStillRunning)"))
        case (.user, .refused(let message)):
            apply(.stopRefused(reason: message))
        case (.exit(let reason), .refused(let message)):
            apply(.stopRefused(reason: "\(reason) \(message)"))
        }
    }
}

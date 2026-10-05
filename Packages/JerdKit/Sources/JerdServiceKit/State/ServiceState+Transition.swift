extension ServiceState {
    /// The one transition rule of the managed-instance state machine. Nil means the event is not
    /// valid in this state, and the caller keeps the current state.
    ///
    /// ```
    /// stopped | failed ──start──▶ starting ──ok──▶ running ──stop | exit──▶ stopping ──ok──▶ stopped
    ///                                │                 ▲                       │  exit ──▶ failed
    ///                                │ error           │                       │  timeout ──▶ stuck
    ///                                ▼                 │                       ▼
    ///                      failed | stuck ◀────────────┘ stuck ──stop──▶ stopping
    /// ```
    public func applying(_ event: ServiceEvent) -> ServiceState? {
        switch (self, event) {
        case (.stopped, .startRequested), (.failed, .startRequested):
            .starting
        case (.starting, .startSucceeded(let pid)):
            .running(pid: pid)
        case (.starting, .startFailed(let reason)):
            .failed(reason: reason)
        case (.starting, .startFailedKeepingProcess(let pid, let reason)):
            .stuck(pid: pid, reason: reason)
        case (.running, .stopRequested(let pid)), (.stuck, .stopRequested(let pid)),
            (.stopping, .stopRequested(let pid)):
            .stopping(pid: pid)
        case (.stopping, .stopSucceeded):
            .stopped
        case (.stopping, .exitReaped(let reason)), (.stopping, .stopRefused(let reason)):
            .failed(reason: reason)
        case (.stopping, .stopTimedOut(let pid, let reason)):
            .stuck(pid: pid, reason: reason)
        case (.stopped, .cleared), (.failed, .cleared):
            .stopped
        case (.stopped, .operationFailed(let reason)), (.failed, .operationFailed(let reason)):
            .failed(reason: reason)
        default:
            nil
        }
    }
}

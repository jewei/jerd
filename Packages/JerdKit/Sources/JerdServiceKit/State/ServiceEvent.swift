import Darwin

/// Something that happened to a managed instance. `ServiceState.applying(_:)` is the only rule
/// that turns an event into a new state.
public enum ServiceEvent: Equatable, Sendable {
    /// A start began.
    case startRequested
    /// The started process passed every check.
    case startSucceeded(pid: pid_t)
    /// The start failed and no process is owned.
    case startFailed(reason: String)
    /// The start failed and the process could not be stopped. It stays owned.
    case startFailedKeepingProcess(pid: pid_t, reason: String)
    /// A graceful stop of the owned process began, by request or after an unexpected exit.
    case stopRequested(pid: pid_t)
    /// The owned process and its group stopped after a requested stop.
    case stopSucceeded
    /// The owned process exited by itself and its group was then stopped.
    case exitReaped(reason: String)
    /// The graceful stop timed out. The process stays owned.
    case stopTimedOut(pid: pid_t, reason: String)
    /// The stop ended without an owned process, but the run record still needs inspection.
    case stopRefused(reason: String)
    /// A Stop found no owned process. A failure message is cleared.
    case cleared
    /// An operation without an owned process failed, for example a runtime update recovery.
    case operationFailed(reason: String)
}

import Darwin

/// The lifecycle state of one managed service instance (a database, the mail inbox, or storage).
///
/// `stuck` replaces the old "failed with a PID": the process is still owned, its data lock is
/// held, and its run record is kept. A Stop leaves `stuck`, and so does exit detection when the
/// kept process and its group ended.
public enum ServiceState: Equatable, Hashable, Sendable {
    /// No process is owned and no error is shown.
    case stopped
    /// A start is in progress.
    case starting
    /// The process passed its readiness and listener checks.
    case running(pid: pid_t)
    /// A graceful stop of the owned process is in progress.
    case stopping(pid: pid_t)
    /// The last operation failed. No process is owned.
    case failed(reason: String)
    /// A process is still owned after a failure or a stop timeout. The lock and the record stay.
    case stuck(pid: pid_t, reason: String)

    /// The short label for a status line.
    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Ready"
        case .stopping: "Stopping…"
        case .failed, .stuck: "Failed"
        }
    }

    /// True while a start or a stop is in progress.
    public var isBusy: Bool {
        switch self {
        case .starting, .stopping: true
        case .stopped, .running, .failed, .stuck: false
        }
    }

    /// The PID of the owned process, when the state names one.
    public var processID: pid_t? {
        switch self {
        case .running(let pid), .stopping(let pid), .stuck(let pid, _): pid
        case .stopped, .starting, .failed: nil
        }
    }

    /// The failure text of `failed` and `stuck`.
    public var failure: String? {
        switch self {
        case .failed(let reason), .stuck(_, let reason): reason
        case .stopped, .starting, .running, .stopping: nil
        }
    }
}

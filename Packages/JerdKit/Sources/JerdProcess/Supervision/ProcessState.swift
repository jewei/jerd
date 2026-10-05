/// The state of a supervised group leader, read without reaping it.
public enum ProcessState: Equatable, Sendable {
    /// The leader has not exited.
    case running
    /// The leader exited with a status. It stays unreaped (and owned) until a stop completes.
    case exited(status: Int32)
    /// A signal ended the leader. It stays unreaped (and owned) until a stop completes.
    case signalled(signal: Int32)
    /// The token is unknown, or the child was reaped outside the supervisor. Jerd owns nothing for it.
    case notOwned

    public var isRunning: Bool { self == .running }

    /// The shell-style status: the exit status, or 128 plus the signal number. Nil while running or not owned.
    public var exitCode: Int32? {
        switch self {
        case .exited(let status): status
        case .signalled(let signal): 128 + signal
        case .running, .notOwned: nil
        }
    }
}

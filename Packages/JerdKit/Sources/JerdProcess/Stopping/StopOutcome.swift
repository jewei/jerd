/// The result of a stop.
public enum StopOutcome: Equatable, Sendable {
    /// The leader and its group stopped. The leader was reaped and the token is released.
    case stopped
    /// The deadline passed. The process stays owned and tracked, so a later stop can retry.
    /// `leaderRunning` is false when only other group members remain.
    case timedOut(leaderRunning: Bool)
    /// Jerd owns no process for the token: it is unknown, or something outside the supervisor
    /// reaped the child. No signal was sent. Group members can still exist; check the run record.
    case notOwned
}

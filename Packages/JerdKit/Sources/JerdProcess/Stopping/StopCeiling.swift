/// The strongest stop that one supervisor runs, fixed when it is created.
///
/// A data service must never get `SIGKILL`. A supervisor with the `.graceful` ceiling runs every
/// policy without the kill step, so a caller that passes `.forceful()` by mistake (or a shared
/// `stopAll`) still cannot kill. The process then stays owned and the stop reports `.timedOut`.
public enum StopCeiling: Equatable, Sendable {
    /// Never `SIGKILL`. The default, for data services and tunnels.
    case graceful
    /// `SIGKILL` after the group deadline is allowed. For Caddy, PHP-FPM, and commands.
    case forceful

    /// `policy` without a kill step when this ceiling forbids it. Signals and deadlines stay.
    public func limit(_ policy: StopPolicy) -> StopPolicy {
        guard self == .graceful, case .kill = policy.escalation else { return policy }
        return StopPolicy(
            signal: policy.signal, leaderTimeout: policy.leaderTimeout, groupTimeout: policy.groupTimeout,
            escalation: .never, sendsSignals: policy.sendsSignals)
    }
}

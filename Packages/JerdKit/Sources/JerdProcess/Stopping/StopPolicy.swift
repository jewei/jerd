import Darwin

/// How to stop a process group. One engine runs both strategies.
///
/// - `forceful`: for Caddy, PHP-FPM, and commands. Signal, wait 3 s, signal the group, wait 2 s,
///   then `SIGKILL` the group and wait a bounded time.
/// - `graceful`: for data services. Signal, wait up to 30 s for the leader and the group together.
///   Never `SIGKILL`. A timeout keeps the process owned.
public struct StopPolicy: Equatable, Sendable {
    /// What happens when the group does not stop in time.
    public enum Escalation: Equatable, Sendable {
        /// Keep the process. The stop reports `timedOut`.
        case never
        /// Send `SIGKILL` to the group, then wait at most this long for the leader.
        case kill(wait: Duration)
    }

    /// The first signal, sent to the leader only.
    public let signal: Int32
    /// How long the leader has to exit after `signal`.
    public let leaderTimeout: Duration
    /// How long the group has after the group `SIGTERM`. Nil means the rest of the leader deadline.
    public let groupTimeout: Duration?
    public let escalation: Escalation
    /// False for a stop that only completes an exit: no signal goes to any process.
    public let sendsSignals: Bool

    public init(
        signal: Int32, leaderTimeout: Duration, groupTimeout: Duration?, escalation: Escalation,
        sendsSignals: Bool = true
    ) {
        self.signal = signal
        self.leaderTimeout = leaderTimeout
        self.groupTimeout = groupTimeout
        self.escalation = escalation
        self.sendsSignals = sendsSignals
    }

    /// Stops with `signal`, then the group `SIGTERM`, then a bounded group `SIGKILL`.
    public static func forceful(
        signal: Int32 = SIGTERM, leaderTimeout: Duration = .seconds(3), groupTimeout: Duration = .seconds(2),
        killWait: Duration = .seconds(2)
    ) -> StopPolicy {
        StopPolicy(
            signal: signal, leaderTimeout: leaderTimeout, groupTimeout: groupTimeout, escalation: .kill(wait: killWait))
    }

    /// Stops with `signal` and one deadline for the leader and the group. Never sends `SIGKILL`.
    public static func graceful(signal: Int32 = SIGTERM, timeout: Duration = .seconds(30)) -> StopPolicy {
        StopPolicy(signal: signal, leaderTimeout: timeout, groupTimeout: nil, escalation: .never)
    }

    /// Sends no signal and does not wait. The stop completes (`.stopped`) only when the leader
    /// already exited and no group member remains; otherwise it reports `.timedOut` at once.
    /// For a kept process that ended after its stop timed out.
    public static let completeExited = StopPolicy(
        signal: SIGTERM, leaderTimeout: .zero, groupTimeout: .zero, escalation: .never, sendsSignals: false)
}

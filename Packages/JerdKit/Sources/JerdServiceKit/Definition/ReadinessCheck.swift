/// How to tell that a started server is ready, and how long to wait.
public struct ReadinessCheck: Sendable {
    /// The answer of one probe.
    public enum ProbeResult: Equatable, Sendable {
        case ready
        /// Not ready yet. The text explains why, for the timeout message.
        case notReady(String)
    }

    /// What the timeout message adds after its first sentence.
    public enum TimeoutDetail: Equatable, Sendable {
        /// The last probe failure, for example a client error.
        case lastFailure
        /// The end of the server log.
        case logTail
    }

    /// Runs one probe. A thrown error counts as "not ready" with the error message.
    public typealias Probe = @Sendable () async throws -> ProbeResult

    public var deadline: Duration
    public var interval: Duration
    /// The failure reported when no probe ran or every probe threw.
    public var initialFailure: String
    /// The first sentence of the timeout message, for example "Database readiness timed out."
    public var timeoutMessage: String
    public var timeoutDetail: TimeoutDetail
    public var probe: Probe

    public init(
        deadline: Duration, interval: Duration, initialFailure: String, timeoutMessage: String,
        timeoutDetail: TimeoutDetail, probe: @escaping Probe
    ) {
        self.deadline = deadline
        self.interval = interval
        self.initialFailure = initialFailure
        self.timeoutMessage = timeoutMessage
        self.timeoutDetail = timeoutDetail
        self.probe = probe
    }
}

/// The deadlines and poll intervals of the readiness checks. Tests use shorter ones.
public struct ReadinessTimings: Equatable, Sendable {
    /// How long PHP-FPM has to create its socket.
    public var socketWait: Duration
    public var socketPoll: Duration
    /// One budget for the HTTPS readiness of all sites together, checked in parallel.
    public var tlsBudget: Duration
    public var tlsPoll: Duration
    /// curl `--max-time` in seconds, and the command timeout around it.
    public var requestSeconds: Int
    public var requestTimeout: Duration
    /// The timeout of each validation command (`php-fpm -t`, `caddy validate`).
    public var validationTimeout: Duration

    public init(
        socketWait: Duration = .seconds(10), socketPoll: Duration = .milliseconds(100),
        tlsBudget: Duration = .seconds(20), tlsPoll: Duration = .milliseconds(150), requestSeconds: Int = 2,
        requestTimeout: Duration = .seconds(4), validationTimeout: Duration = .seconds(15)
    ) {
        self.socketWait = socketWait
        self.socketPoll = socketPoll
        self.tlsBudget = tlsBudget
        self.tlsPoll = tlsPoll
        self.requestSeconds = requestSeconds
        self.requestTimeout = requestTimeout
        self.validationTimeout = validationTimeout
    }
}

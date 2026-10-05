/// The result of readiness polling.
public enum ReadinessOutcome: Equatable, Sendable {
    /// A probe reported ready while the process was alive.
    case ready
    /// The process was not alive before a probe passed.
    case exited
    /// The deadline passed. The text is the last redacted probe failure.
    case timedOut(lastFailure: String)
}

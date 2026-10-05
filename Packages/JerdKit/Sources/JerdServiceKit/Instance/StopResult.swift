/// The result of one stop of an owned process, after the instance has settled its ownership.
enum StopResult: Equatable, Sendable {
    /// The process and its group stopped. The record and the temporary items are gone.
    case stopped
    /// The graceful stop timed out. The process, the lock, and the record stay.
    case timedOut(String)
    /// The process was reaped outside Jerd and its record still needs inspection. The lock was
    /// released so that process recovery can act; the record blocks every start meanwhile.
    case refused(String)

    /// The user message of a failed stop, or nil after success.
    var failureMessage: String? {
        switch self {
        case .stopped: nil
        case .timedOut(let message), .refused(let message): message
        }
    }
}

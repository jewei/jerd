/// The state of the one operation that a feature model runs at a time. A failure stays until
/// the user dismisses it or the next operation starts, and only the owning page shows it.
public enum OperationState: Equatable, Sendable {
    case idle
    /// Work runs. `canStop` is true when the user can stop it from the page.
    case working(message: String, canStop: Bool)
    case failed(message: String)

    /// A working operation that cannot be stopped.
    public static func working(_ message: String) -> OperationState {
        .working(message: message, canStop: false)
    }

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    /// The progress message while work runs.
    public var workingMessage: String? {
        if case .working(let message, _) = self { return message }
        return nil
    }

    /// The message of a failed operation.
    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

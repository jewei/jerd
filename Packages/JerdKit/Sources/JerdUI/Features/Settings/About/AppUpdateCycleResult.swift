/// How an update cycle ended. The adapter maps Sparkle errors to these cases.
public enum AppUpdateCycleResult: Equatable, Sendable {
    /// The cycle ended without an error, for example after an update was found.
    case completed
    /// Sparkle reports `noUpdateError`.
    case noUpdate
    /// The user cancelled the installation or the check.
    case cancelled
    /// Any other error, with its description.
    case failed(String)
}

/// The state of the serving engine and of the environment coordinator, as the app shows it.
public enum EnvironmentState: Equatable, Hashable, Sendable {
    /// HTTPS setup was removed; sites need approval before they can start.
    case setupRequired
    case starting
    case running
    /// Not running. A cancelled start also ends here, never in `failed`.
    case stopped
    /// The last start or run failed. The message is the one the user sees.
    case failed(String)
}

/// The state of one tunnel connector as the app shows it.
public enum TunnelState: Equatable, Hashable, Sendable {
    /// No connector runs.
    case stopped
    /// Jerd prepares and launches the connector.
    case starting
    /// The connector runs and has not reported an edge connection yet in this Connect.
    case connecting
    /// The connector reports at least one edge connection. The website itself is not checked.
    case connected
    /// The connector lost its edge connections, or Jerd waits to start a new connector.
    case reconnecting
    /// Jerd stops the connector gracefully.
    case stopping
    /// The connector needs the user. The text says why.
    case failed(String)

    /// The badge text.
    public var title: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting…"
        case .stopping: "Stopping…"
        case .failed: "Needs attention"
        }
    }

    /// True while a connector runs or a Connect or Stop is in progress.
    public var isActive: Bool {
        switch self {
        case .starting, .connecting, .connected, .reconnecting, .stopping: true
        case .stopped, .failed: false
        }
    }

    /// The reason of `.failed`, else nil.
    public var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

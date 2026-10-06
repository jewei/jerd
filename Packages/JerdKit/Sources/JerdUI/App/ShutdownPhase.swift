/// One stage of the staged quit. The case order is the stop order and must not change:
/// pending site work, runtime work, tunnels, storage, mail, databases, then PHP-FPM and Caddy.
public enum ShutdownPhase: Int, CaseIterable, Comparable, Sendable {
    /// Cancels or waits for the current site or HTTPS setup operation.
    case siteWork
    /// Cancels a runtime check and an installation that is not activating yet.
    case runtimeWork
    case tunnels
    case storage
    case mail
    case databases
    /// PHP-FPM, Caddy, and the helper connection.
    case webEnvironment

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The banner message while the stage runs. A participant can give a more exact one.
    public var message: String {
        switch self {
        case .siteWork: "Cancelling preparation…"
        case .runtimeWork: "Finishing runtime changes…"
        case .tunnels: "Stopping Cloudflare tunnels…"
        case .storage: "Stopping storage…"
        case .mail: "Stopping mail…"
        case .databases: "Stopping databases safely…"
        case .webEnvironment: "Stopping PHP-FPM and Caddy…"
        }
    }

    /// The message when the stage cannot stop safely. Jerd then stays open.
    public var failureMessage: String {
        switch self {
        case .siteWork:
            "The current site operation could not finish safely. Jerd will remain open. Check Sites and try again."
        case .runtimeWork:
            "A runtime change could not finish safely. Jerd will remain open. Check Runtimes and try again."
        case .tunnels: "A tunnel could not stop safely. Jerd will remain open. Retry Stop in Sites."
        case .storage: "Storage could not stop safely. Jerd will remain open. Retry Stop in Storage."
        case .mail: "The mail service could not stop safely. Jerd will remain open. Retry Stop in Mail."
        case .databases:
            "A database service could not stop safely. Jerd will remain open. Check Databases and retry Stop."
        case .webEnvironment:
            "PHP-FPM or Caddy could not stop safely. Jerd will remain open. Retry Stop All Sites in Sites."
        }
    }

    /// Where the window goes when the stage fails, so the user sees the item to retry.
    public var failureDestination: Destination {
        switch self {
        case .siteWork, .tunnels, .webEnvironment: .section(.sites)
        case .runtimeWork: .dashboard(.runtimes)
        case .storage: .section(.storage)
        case .mail: .section(.mail)
        case .databases: .section(.databases)
        }
    }
}

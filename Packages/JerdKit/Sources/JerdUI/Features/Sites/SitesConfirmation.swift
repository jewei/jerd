import JerdWeb

/// A step on the Sites page that changes data or the system, and its confirmation text.
public enum SitesConfirmation: Equatable, Sendable {
    case removeSite(Site)
    case removeSystemSetup
    case reconnectHelper

    public var title: String {
        switch self {
        case .removeSite: "Remove this registration?"
        case .removeSystemSetup: "Remove Jerd system setup?"
        case .reconnectHelper: "Reconnect the Jerd helper?"
        }
    }

    public var message: String {
        switch self {
        case .removeSite:
            "Jerd will remove this site’s registered host. Other running sites will restart. The CA remains trusted while other hosts are registered. The project folder and its files stay on disk; Jerd never deletes them."
        case .removeSystemSetup:
            "Jerd will stop the environment, remove its host entries and CA certificate, then unregister its helper. Site records and project files will remain."
        case .reconnectHelper:
            "Jerd will stop its sites and register its system helper again. macOS can ask for approval. Existing hosts, certificate settings, and project files will remain. Start your sites after reconnection."
        }
    }

    public var confirmTitle: String {
        switch self {
        case .removeSite: "Remove Registration"
        case .removeSystemSetup: "Remove System Setup"
        case .reconnectHelper: "Reconnect Helper"
        }
    }

    /// Destructive steps use the destructive role and never confirm with Return.
    public var isDestructive: Bool {
        switch self {
        case .removeSite, .removeSystemSetup: true
        case .reconnectHelper: false
        }
    }

    /// The banner message while the step runs.
    public var workingMessage: String {
        switch self {
        case .removeSite: "Removing the site registration. Complete or cancel any macOS approval prompt…"
        case .removeSystemSetup: "Removing HTTPS setup. Complete or cancel the macOS approval prompt…"
        case .reconnectHelper: "Reconnecting the helper. Complete any macOS approval prompt…"
        }
    }
}

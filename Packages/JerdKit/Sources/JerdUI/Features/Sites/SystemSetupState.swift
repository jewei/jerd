import JerdDesign

/// A state of the HTTPS system setup that the Sites page explains in a banner.
public enum SystemSetupState: Equatable, Sendable {
    /// The setup was removed. The next Start asks for approval.
    case approvalRequired
    /// The approved setup is being applied. macOS can show a prompt.
    case inProgress(String)
    /// An interrupted setup waits for recovery in Advanced. No site can change until then.
    case recoveryPending
    /// The helper could not report the setup.
    case unreadable(String)

    public var kind: MessageKind {
        switch self {
        case .approvalRequired, .inProgress: .info
        case .recoveryPending: .warning
        case .unreadable: .error
        }
    }

    public var title: String {
        switch self {
        case .approvalRequired: "HTTPS approval required"
        case .inProgress: "Setting up HTTPS"
        case .recoveryPending: "HTTPS setup needs recovery"
        case .unreadable: "HTTPS setup unknown"
        }
    }

    public var message: String {
        switch self {
        case .approvalRequired:
            "Jerd’s host entries and CA trust were removed. Start a site to review and approve them again."
        case .inProgress(let message): message
        case .recoveryPending:
            "An earlier HTTPS setup was interrupted. Recover it in Advanced before you start or change sites."
        case .unreadable(let message): "Jerd could not read the HTTPS setup. \(message)"
        }
    }

    /// Only a pending recovery links to another page.
    public var opensAdvanced: Bool { self == .recoveryPending }
}

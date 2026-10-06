import JerdTunnels

/// A tunnel step that asks first: Connect (it can share traffic) and Remove.
public enum TunnelConfirmation: Equatable, Sendable {
    case connect(TunnelRegistration)
    case remove(TunnelRegistration)

    public var title: String {
        switch self {
        case .connect(let tunnel): "Connect \(tunnel.name)?"
        case .remove: "Remove this tunnel from Jerd?"
        }
    }

    public var message: String {
        switch self {
        case .connect:
            "Jerd will start another connector for this existing tunnel. Cloudflare can send traffic to it alongside any connector that is already running. Confirm that the existing routes point to services on this Mac."
        case .remove:
            "Jerd will stop its connector and remove its saved token. The Cloudflare tunnel, DNS settings, and other connectors will remain."
        }
    }

    public var confirmTitle: String {
        switch self {
        case .connect: "Connect"
        case .remove: "Remove Registration"
        }
    }

    public var isDestructive: Bool {
        if case .remove = self { return true }
        return false
    }
}

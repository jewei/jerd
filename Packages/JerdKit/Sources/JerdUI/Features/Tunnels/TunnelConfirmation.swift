import JerdTunnels

/// A tunnel step that asks first: Connect (it can share traffic) and Remove.
public enum TunnelConfirmation: Equatable, Sendable {
    /// `destination` is the local address of a Jerd route, so the user sees what becomes public.
    case connect(TunnelRegistration, destination: String? = nil)
    case remove(TunnelRegistration)

    public var title: String {
        switch self {
        case .connect(let tunnel, _): "Connect \(tunnel.name)?"
        case .remove: "Remove this tunnel from Jerd?"
        }
    }

    public var message: String {
        switch self {
        case .connect(let tunnel, let destination) where tunnel.routing == .local:
            "Jerd will send https://\(tunnel.hostname) to \(destination ?? "the local destination of this tunnel"). Cloudflare can also send this traffic to other connectors of this tunnel."
        case .connect:
            "Jerd will start another connector for this existing tunnel. Cloudflare can send traffic to it alongside any connector that is already running. Confirm that the existing routes point to services on this Mac."
        case .remove(let tunnel) where tunnel.cloudflare != nil:
            "Jerd will stop its connector and remove its saved token. Jerd created this tunnel, so it can also delete the tunnel and its DNS record in Cloudflare."
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

    /// The second button of Remove for a tunnel that Jerd created, or nil.
    public var cloudflareDeleteTitle: String? {
        if case .remove(let tunnel) = self, tunnel.cloudflare != nil { return "Remove and Delete in Cloudflare" }
        return nil
    }

    public var isDestructive: Bool {
        if case .remove = self { return true }
        return false
    }
}

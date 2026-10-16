/// Where a new tunnel comes from: Jerd creates it in Cloudflare, or the user pastes the token of
/// an existing tunnel.
public enum TunnelSource: String, CaseIterable, Sendable {
    case create
    case existing

    public var title: String {
        switch self {
        case .create: "Create in Cloudflare"
        case .existing: "Use an existing token"
        }
    }
}

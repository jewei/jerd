/// Where the connector gets the route from the public hostname to the local service.
public enum TunnelRouting: String, Codable, CaseIterable, Sendable {
    case local
    case cloudflare
}

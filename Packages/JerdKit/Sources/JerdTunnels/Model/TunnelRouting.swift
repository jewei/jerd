/// Where the connector gets the route from the public hostname to the local service.
///
/// The raw values are saved in `tunnels/settings.json`; do not rename them.
public enum TunnelRouting: String, Codable, CaseIterable, Sendable {
    /// Jerd writes the route to `config.yml`. Only a locally managed tunnel uses it.
    case local
    /// The Cloudflare dashboard sends the route. Registrations of earlier builds use this value.
    case cloudflare
}

/// The connected Cloudflare account. It creates and deletes only the tunnels and DNS records
/// that Jerd creates, and never replaces an existing record.
public protocol CloudflareProvisioning: Sendable {
    /// True when an API token is saved.
    func isConnected() async throws -> Bool
    /// Checks the API token, saves it in the Keychain, and returns its zones.
    func connect(apiToken: String) async throws -> [CloudflareZone]
    /// Removes the saved API token. Tunnels and DNS records stay.
    func disconnect() async throws
    /// The zones that the saved API token can edit.
    func zones() async throws -> [CloudflareZone]
    /// Creates a locally managed tunnel and a proxied CNAME for `hostname`. A failure after the
    /// tunnel exists deletes the tunnel again.
    func provision(hostname: String, zone: CloudflareZone, tunnelName: String) async throws -> CloudflareProvision
    /// Deletes the DNS record and the tunnel of `record`. Resources that are already gone are fine.
    func deprovision(_ record: CloudflareTunnelRecord) async throws
}

/// A tunnel that Jerd created: its connector token and the record of what to delete later.
public struct CloudflareProvision: Equatable, Sendable {
    public let token: TunnelToken
    public let record: CloudflareTunnelRecord

    public init(token: TunnelToken, record: CloudflareTunnelRecord) {
        self.token = token
        self.record = record
    }
}

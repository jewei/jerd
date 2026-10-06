import Foundation
import JerdTunnels

/// The cloudflared connectors for existing Cloudflare tunnels. JerdLive implements it with
/// `TunnelSupervisor`. No call changes a Cloudflare account, a route, or DNS.
public protocol TunnelsPort: Sendable {
    /// Reads the saved settings once. It never connects a tunnel.
    /// - Throws: When the file cannot be read. The file stays as it is.
    func load() async throws -> TunnelConfiguration
    /// The settings as last loaded or saved.
    func configuration() async -> TunnelConfiguration
    /// One snapshot per registration, in settings order.
    func snapshots() async -> [TunnelSnapshot]
    /// A free metrics port that no registration uses.
    func suggestedPort() async throws -> UInt16
    /// Adds or changes a registration. A token replaces the saved one; nil keeps it. Save
    /// never connects.
    func save(_ registration: TunnelRegistration, token: String?) async throws
    /// Removes a registration and its token. The tunnel and DNS at Cloudflare stay.
    func remove(id: UUID) async throws
    /// Starts a connector for one tunnel.
    func connect(id: UUID) async throws
    /// Stops one connector gracefully. A connector that does not stop stays owned.
    func stop(id: UUID) async throws
    /// Stops every connector for Quit. Throws when one still runs.
    func stopAll() async throws
    /// Connects every tunnel with "Start when Jerd opens". Every failure is returned.
    func connectStartupTunnels() async throws -> [TunnelStartupFailure]
    /// The recent connector output, with the token redacted.
    func log(id: UUID) async throws -> String
    /// Checks a trusted cloudflared executable and uses it for every tunnel.
    func useRuntime(at executable: URL) async throws -> TunnelRuntime
}

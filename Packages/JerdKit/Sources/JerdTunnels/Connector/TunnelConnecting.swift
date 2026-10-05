import Foundation

/// Starts, checks, and stops cloudflared connectors that Jerd owns. `TunnelSupervisor` depends on this
/// role so that its tests use a fake and never start a real tunnel.
public protocol TunnelConnecting: Sendable {
    /// Runs `<executable> --version` and returns the checked runtime.
    func inspectRuntime(executable: URL) async throws -> TunnelRuntime
    /// The first free loopback port from `first` that is not in `reserved`.
    func suggestPort(startingAt first: UInt16, excluding reserved: Set<UInt16>) async throws -> UInt16
    /// Launches one connector. It returns when the process runs, not when it is connected.
    func connect(_ launch: TunnelLaunch) async throws -> TunnelConnectorHandle
    /// The connector that Jerd still owns for a registration, also after a failed launch or stop.
    func ownedHandle(for id: UUID) async -> TunnelConnectorHandle?
    /// True while the owned connector process has not exited.
    func isRunning(_ handle: TunnelConnectorHandle) async -> Bool
    /// Checks the loopback metrics listener and `/ready`. Throws when the check cannot finish.
    func readiness(of handle: TunnelConnectorHandle) async throws -> TunnelReadiness
    /// Stops the connector gracefully. Throws when it still runs; it then stays owned.
    func disconnect(_ handle: TunnelConnectorHandle) async throws
    /// The recent output of the current connector run only.
    func currentOutput(for id: UUID) async throws -> String
    /// The recent output of this and earlier runs, or nil when no connector ever ran.
    func history(for id: UUID) async throws -> String?
}

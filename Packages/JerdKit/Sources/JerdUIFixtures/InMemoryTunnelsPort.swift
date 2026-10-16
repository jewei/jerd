import Foundation
import JerdFoundation
import JerdTunnels
import JerdUI

/// Tunnel settings and connector states in memory. Save never connects; Connect goes straight
/// to Connected unless a failure is set.
public actor InMemoryTunnelsPort: TunnelsPort {
    public var configurationValue: TunnelConfiguration
    public var states: [UUID: TunnelState]
    /// Saved tokens by tunnel. A test can check that Save sent one and that Cancel did not.
    public private(set) var tokens: [UUID: String] = [:]
    public var failure: String?
    public var loadFailure: String?
    /// When true, Stop leaves the connector running and throws.
    public var stopFails = false
    public var startupFailures: [TunnelStartupFailure] = []
    /// When set, Save waits at this gate, so a test can cancel the editor during the save.
    public var saveGate: FixtureGate?
    public var logText = SampleData.tunnelLog
    public var suggestedPortValue: UInt16 = 20_243
    /// True when a Cloudflare API token is saved.
    public var cloudflareConnected = false
    public var zones = SampleData.cloudflareZones
    /// The message of a failed Cloudflare call: Connect, Create, or Remove from Cloudflare.
    public var cloudflareFailure: String?
    /// The DNS answer for each public hostname. A name without a value resolves.
    public var hostnameStatuses: [String: PublicHostnameStatus] = [:]
    public private(set) var calls: [String] = []

    /// By default the sample tunnels run as the user left them: Studio preview is connected.
    public init(
        configuration: TunnelConfiguration = SampleData.tunnelConfiguration,
        states: [UUID: TunnelState] = SampleData.tunnelStates,
        hostnameStatuses: [String: PublicHostnameStatus] = [:]
    ) {
        configurationValue = configuration
        self.states = states
        self.hostnameStatuses = hostnameStatuses
    }

    public func configure(_ change: @Sendable (isolated InMemoryTunnelsPort) -> Void) {
        change(self)
    }

    public func load() async throws -> TunnelConfiguration {
        if let loadFailure { throw JerdError.corrupt(loadFailure) }
        return configurationValue
    }

    public func configuration() async -> TunnelConfiguration { configurationValue }

    public func snapshots() async -> [TunnelSnapshot] {
        configurationValue.tunnels.map { TunnelSnapshot(registration: $0, state: states[$0.id] ?? .stopped) }
    }

    public func suggestedPort() async throws -> UInt16 { suggestedPortValue }

    public func save(_ registration: TunnelRegistration, token: String?) async throws {
        if let saveGate { await saveGate.pass() }
        try record("save \(registration.hostname) token=\(token != nil)")
        if let token { tokens[registration.id] = token }
        if let index = configurationValue.tunnels.firstIndex(where: { $0.id == registration.id }) {
            configurationValue.tunnels[index] = registration
        } else {
            configurationValue.tunnels.append(registration)
        }
    }

    public func remove(id: UUID) async throws {
        try record("remove \(id.uuidString.prefix(8))")
        configurationValue.tunnels.removeAll { $0.id == id }
        tokens[id] = nil
    }

    public func isCloudflareConnected() async throws -> Bool { cloudflareConnected }

    public func connectCloudflare(apiToken: String) async throws -> [CloudflareZone] {
        try recordCloudflare("connect cloudflare")
        cloudflareConnected = true
        return zones
    }

    public func disconnectCloudflare() async throws {
        try record("disconnect cloudflare")
        cloudflareConnected = false
    }

    public func cloudflareZones() async throws -> [CloudflareZone] { zones }

    /// Adds the registration with a sample record, as Create does.
    public func create(_ registration: TunnelRegistration, in zone: CloudflareZone) async throws {
        try recordCloudflare("create \(registration.hostname) in \(zone.name)")
        var created = registration
        created.cloudflare = SampleData.cloudflareRecord
        configurationValue.tunnels.append(created)
    }

    public func removeFromCloudflare(id: UUID) async throws {
        try recordCloudflare("remove from cloudflare \(id.uuidString.prefix(8))")
        configurationValue.tunnels.removeAll { $0.id == id }
    }

    public func connect(id: UUID) async throws {
        try record("connect \(id.uuidString.prefix(8))")
        states[id] = .connected
    }

    public func stop(id: UUID) async throws {
        try record("stop \(id.uuidString.prefix(8))")
        if stopFails { throw JerdError.unavailable("The tunnel has not stopped. Retry Stop.") }
        states[id] = .stopped
    }

    public func stopAll() async throws {
        try record("stop all")
        if stopFails { throw JerdError.unavailable("The tunnel has not stopped. Retry Stop.") }
        states = [:]
    }

    public func connectStartupTunnels() async throws -> [TunnelStartupFailure] {
        calls.append("connect startup")
        for tunnel in configurationValue.tunnels where tunnel.startOnLaunch && tunnel.canConnectOnLaunch {
            if !startupFailures.contains(where: { $0.id == tunnel.id }) { states[tunnel.id] = .connected }
        }
        return startupFailures
    }

    public func log(id: UUID) async throws -> String {
        try record("log")
        return logText
    }

    public func publicHostnameStatus(_ hostname: String) async -> PublicHostnameStatus {
        calls.append("look up \(hostname)")
        return hostnameStatuses[hostname] ?? .resolves
    }

    public func useRuntime(at executable: URL) async throws -> TunnelRuntime {
        try record("use runtime \(executable.path)")
        let runtime = TunnelRuntime(version: "2025.9.1", directory: executable.deletingLastPathComponent())
        configurationValue.runtime = runtime
        return runtime
    }

    private func recordCloudflare(_ call: String) throws {
        try record(call)
        if let cloudflareFailure { throw JerdError.unavailable(cloudflareFailure) }
    }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw JerdError.unavailable(failure) }
    }
}

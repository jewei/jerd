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
    public var logText = SampleData.tunnelLog
    public var suggestedPortValue: UInt16 = 20_243
    public private(set) var calls: [String] = []

    public init(
        configuration: TunnelConfiguration = SampleData.tunnelConfiguration, states: [UUID: TunnelState] = [:]
    ) {
        configurationValue = configuration
        self.states = states
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
        for tunnel in configurationValue.tunnels where tunnel.startOnLaunch {
            if !startupFailures.contains(where: { $0.id == tunnel.id }) { states[tunnel.id] = .connected }
        }
        return startupFailures
    }

    public func log(id: UUID) async throws -> String {
        try record("log")
        return logText
    }

    public func useRuntime(at executable: URL) async throws -> TunnelRuntime {
        try record("use runtime \(executable.path)")
        let runtime = TunnelRuntime(version: "2025.9.1", directory: executable.deletingLastPathComponent())
        configurationValue.runtime = runtime
        return runtime
    }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw JerdError.unavailable(failure) }
    }
}

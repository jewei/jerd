import Foundation
import JerdTunnels

/// The tunnel supervisor calls that the live ports use. `TunnelSupervisor` is the live type.
package protocol TunnelControlling: Sendable {
    func load() async throws -> TunnelConfiguration
    func currentConfiguration() async -> TunnelConfiguration
    func snapshots() async -> [TunnelSnapshot]
    func suggestedPort() async throws -> UInt16
    func save(_ registration: TunnelRegistration, token text: String?) async throws
    func remove(id: UUID) async throws
    func start(id: UUID) async throws
    func stop(id: UUID) async throws
    func stopAll() async throws
    func connectStartupTunnels() async throws -> [TunnelStartupFailure]
    func log(id: UUID) async throws -> String
    func useRuntime(at executable: URL) async throws -> TunnelRuntime
}

extension TunnelSupervisor: TunnelControlling {}

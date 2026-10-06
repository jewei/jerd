import Foundation
import JerdTunnels
import JerdUI

/// The Tunnels port on the one `TunnelSupervisor`. The model calls `connectStartupTunnels()`
/// right after a successful `load()`; `stopAll()` throws while a connector still runs, which
/// cancels Quit.
package struct LiveTunnelsPort: TunnelsPort {
    let supervisor: any TunnelControlling

    package init(supervisor: any TunnelControlling) {
        self.supervisor = supervisor
    }

    package func load() async throws -> TunnelConfiguration {
        try await supervisor.load()
    }

    package func configuration() async -> TunnelConfiguration {
        await supervisor.currentConfiguration()
    }

    package func snapshots() async -> [TunnelSnapshot] {
        await supervisor.snapshots()
    }

    package func suggestedPort() async throws -> UInt16 {
        try await supervisor.suggestedPort()
    }

    package func save(_ registration: TunnelRegistration, token: String?) async throws {
        try await supervisor.save(registration, token: token)
    }

    package func remove(id: UUID) async throws {
        try await supervisor.remove(id: id)
    }

    package func connect(id: UUID) async throws {
        try await supervisor.start(id: id)
    }

    package func stop(id: UUID) async throws {
        try await supervisor.stop(id: id)
    }

    package func stopAll() async throws {
        try await supervisor.stopAll()
    }

    package func connectStartupTunnels() async throws -> [TunnelStartupFailure] {
        try await supervisor.connectStartupTunnels()
    }

    package func log(id: UUID) async throws -> String {
        try await supervisor.log(id: id)
    }

    package func useRuntime(at executable: URL) async throws -> TunnelRuntime {
        try await supervisor.useRuntime(at: executable)
    }
}

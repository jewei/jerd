import Foundation
import JerdTunnels
import JerdUI

/// The Tunnels port on the one `TunnelSupervisor`. The model calls `connectStartupTunnels()`
/// right after a successful `load()`; `stopAll()` throws while a connector still runs, which
/// cancels Quit.
package struct LiveTunnelsPort: TunnelsPort {
    let supervisor: any TunnelControlling
    let cloudflare: any CloudflareProvisioning
    let hostnames: any PublicHostnameResolving

    package init(
        supervisor: any TunnelControlling, cloudflare: any CloudflareProvisioning,
        hostnames: any PublicHostnameResolving = PublicHostnameResolver()
    ) {
        self.supervisor = supervisor
        self.cloudflare = cloudflare
        self.hostnames = hostnames
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

    package func isCloudflareConnected() async throws -> Bool {
        try await cloudflare.isConnected()
    }

    package func connectCloudflare(apiToken: String) async throws -> [CloudflareZone] {
        try await cloudflare.connect(apiToken: apiToken)
    }

    package func disconnectCloudflare() async throws {
        try await cloudflare.disconnect()
    }

    package func cloudflareZones() async throws -> [CloudflareZone] {
        try await cloudflare.zones()
    }

    package func create(_ registration: TunnelRegistration, in zone: CloudflareZone) async throws {
        ServiceActivityLog.request("Create", "tunnel \(registration.id) in Cloudflare")
        try await supervisor.create(registration, in: zone)
    }

    package func removeFromCloudflare(id: UUID) async throws {
        ServiceActivityLog.request("Delete", "tunnel \(id) in Cloudflare")
        try await supervisor.removeFromCloudflare(id: id)
    }

    package func connect(id: UUID) async throws {
        ServiceActivityLog.request("Start", "tunnel \(id)")
        try await supervisor.start(id: id)
    }

    package func stop(id: UUID) async throws {
        ServiceActivityLog.request("Stop", "tunnel \(id)")
        try await supervisor.stop(id: id)
    }

    package func stopAll() async throws {
        ServiceActivityLog.request("Stop", "every tunnel")
        try await supervisor.stopAll()
    }

    package func connectStartupTunnels() async throws -> [TunnelStartupFailure] {
        ServiceActivityLog.request("Start", "the tunnels marked Start when Jerd opens")
        return try await supervisor.connectStartupTunnels()
    }

    package func log(id: UUID) async throws -> String {
        try await supervisor.log(id: id)
    }

    package func publicHostnameStatus(_ hostname: String) async -> PublicHostnameStatus {
        await hostnames.status(of: hostname)
    }

    package func useRuntime(at executable: URL) async throws -> TunnelRuntime {
        try await supervisor.useRuntime(at: executable)
    }
}

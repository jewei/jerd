import Foundation
import JerdFoundation
import JerdTunnels
import Testing

@testable import JerdLive

@Suite("Live Tunnels port")
struct LiveTunnelsPortTests {
    @Test func loadNeverConnectsAndStartupConnectionsAreASeparateCall() async throws {
        let supervisor = RecordingTunnelSupervisor()
        let port = LiveTunnelsPort(supervisor: supervisor, cloudflare: FakeCloudflareAccount())

        _ = try await port.load()
        #expect(await supervisor.calls == ["load"])

        _ = try await port.connectStartupTunnels()
        #expect(await supervisor.calls == ["load", "connectStartupTunnels"])
    }

    @Test func connectStartsTheConnectorOfThatTunnel() async throws {
        let supervisor = RecordingTunnelSupervisor()
        let id = UUID()

        try await LiveTunnelsPort(supervisor: supervisor, cloudflare: FakeCloudflareAccount()).connect(id: id)

        #expect(await supervisor.calls == ["start \(id)"])
    }

    @Test func aConnectorThatStillRunsCancelsTheQuit() async throws {
        let supervisor = RecordingTunnelSupervisor()
        await supervisor.failStopAll(.timedOut("A connector did not stop."))

        await #expect(throws: JerdError.timedOut("A connector did not stop.")) {
            try await LiveTunnelsPort(supervisor: supervisor, cloudflare: FakeCloudflareAccount()).stopAll()
        }
    }

    @Test func useRuntimePassesTheExecutable() async throws {
        let supervisor = RecordingTunnelSupervisor()
        let executable = URL(fileURLWithPath: "/runtimes/cloudflared/cloudflared")

        let runtime = try await LiveTunnelsPort(supervisor: supervisor, cloudflare: FakeCloudflareAccount()).useRuntime(
            at: executable)

        #expect(runtime.path == "/runtimes/cloudflared")
        #expect(await supervisor.calls == ["useRuntime /runtimes/cloudflared/cloudflared"])
    }

    @Test func hostnameLookupUsesTheResolverAndNotTheSupervisor() async {
        let supervisor = RecordingTunnelSupervisor()
        let resolver = FakePublicHostnameResolver(answer: .missing)
        let port = LiveTunnelsPort(supervisor: supervisor, cloudflare: FakeCloudflareAccount(), hostnames: resolver)

        #expect(await port.publicHostnameStatus("dev.example.com") == .missing)
        #expect(await resolver.hostnames == ["dev.example.com"])
        #expect(await supervisor.calls.isEmpty)
    }

    @Test func createAndRemoveFromCloudflareGoThroughTheSupervisor() async throws {
        let supervisor = RecordingTunnelSupervisor()
        let account = FakeCloudflareAccount()
        let port = LiveTunnelsPort(supervisor: supervisor, cloudflare: account)
        let zone = CloudflareZone(id: String(repeating: "b", count: 32), name: "example.com", accountID: "a")

        try await port.create(TunnelRegistration(name: "A", hostname: "a.example.com"), in: zone)
        try await port.removeFromCloudflare(id: UUID())
        try await port.disconnectCloudflare()

        #expect(await supervisor.calls == ["create example.com", "removeFromCloudflare"])
        #expect(await account.calls == ["disconnect"])
    }

    /// Stop is written to the app log, as Connect is.
    @Test func stopAndStopAllAreWrittenToTheAppLogLikeConnect() async throws {
        let start = Date().addingTimeInterval(-1)
        let port = LiveTunnelsPort(supervisor: RecordingTunnelSupervisor(), cloudflare: FakeCloudflareAccount())
        let id = UUID()

        try await port.connect(id: id)
        try await port.stop(id: id)
        try await port.stopAll()

        let messages = try AppLogEntries.serviceMessages(since: start)
        #expect(messages.contains("Start requested for tunnel \(id)."))
        #expect(messages.contains("Stop requested for tunnel \(id)."))
        #expect(messages.contains("Stop requested for every tunnel."))
    }
}

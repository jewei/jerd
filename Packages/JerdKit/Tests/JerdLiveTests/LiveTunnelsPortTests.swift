import Foundation
import JerdFoundation
import Testing

@testable import JerdLive

@Suite("Live Tunnels port")
struct LiveTunnelsPortTests {
    @Test func loadNeverConnectsAndStartupConnectionsAreASeparateCall() async throws {
        let supervisor = RecordingTunnelSupervisor()
        let port = LiveTunnelsPort(supervisor: supervisor)

        _ = try await port.load()
        #expect(await supervisor.calls == ["load"])

        _ = try await port.connectStartupTunnels()
        #expect(await supervisor.calls == ["load", "connectStartupTunnels"])
    }

    @Test func connectStartsTheConnectorOfThatTunnel() async throws {
        let supervisor = RecordingTunnelSupervisor()
        let id = UUID()

        try await LiveTunnelsPort(supervisor: supervisor).connect(id: id)

        #expect(await supervisor.calls == ["start \(id)"])
    }

    @Test func aConnectorThatStillRunsCancelsTheQuit() async throws {
        let supervisor = RecordingTunnelSupervisor()
        await supervisor.failStopAll(.timedOut("A connector did not stop."))

        await #expect(throws: JerdError.timedOut("A connector did not stop.")) {
            try await LiveTunnelsPort(supervisor: supervisor).stopAll()
        }
    }

    @Test func useRuntimePassesTheExecutable() async throws {
        let supervisor = RecordingTunnelSupervisor()
        let executable = URL(fileURLWithPath: "/runtimes/cloudflared/cloudflared")

        let runtime = try await LiveTunnelsPort(supervisor: supervisor).useRuntime(at: executable)

        #expect(runtime.path == "/runtimes/cloudflared")
        #expect(await supervisor.calls == ["useRuntime /runtimes/cloudflared/cloudflared"])
    }

    /// Review final-domain-r1 L3: Stop is written to the app log, as Connect is.
    @Test func stopAndStopAllAreWrittenToTheAppLogLikeConnect() async throws {
        let start = Date().addingTimeInterval(-1)
        let port = LiveTunnelsPort(supervisor: RecordingTunnelSupervisor())
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

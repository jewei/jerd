import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import JerdTunnels
import Testing

/// Runs the real process layer with a fake `cloudflared` script that prints its environment.
/// No tunnel starts and nothing leaves the Mac; the user's own cloudflared is never used.
@Suite(.timeLimit(.minutes(1))) struct CloudflaredRedactionTests {
    private static let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "cloudflared version 2026.9.3 (built today)"; exit 0; fi
        echo "token=$TUNNEL_TOKEN"
        echo "args=$*"
        echo "home=$HOME"
        exec /bin/sleep 30
        """

    @Test func theTokenAndItsSecretNeverReachTheLogOrTheArguments() async throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        let runtimeFolder = folder.url.appendingPathComponent("runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeFolder, withIntermediateDirectories: true)
        let executable = runtimeFolder.appendingPathComponent("cloudflared")
        try Data(Self.script.utf8).write(to: executable)
        chmod(executable.path, 0o700)
        let port = try await LoopbackPortGuard().suggest(startingAt: 47_100)
        let connector = CloudflaredConnector(layout: folder.layout)
        let runtime = try await connector.inspectRuntime(executable: executable)
        let registration = TunnelRegistration(name: "Preview", hostname: "preview.example.com", metricsPort: port)
        let token = try TunnelToken(TokenSamples.valid)
        let handle = try await connector.connect(
            TunnelLaunch(runtime: runtime, registration: registration, token: token))
        let instance = folder.layout.instance(registration.id)
        await waitUntil { text(instance.logFile).contains("home=") }
        try await connector.disconnect(handle)
        let log = text(instance.logFile)
        #expect(log.contains("token=\(LogRedactor.marker)\n"))
        #expect(log.contains("args=tunnel --config \(instance.configurationFile.path) --no-autoupdate"))
        #expect(log.contains("home=\(instance.homeDirectory.path)\n"))
        #expect(!log.contains(TokenSamples.valid))
        #expect(!log.contains(TokenSamples.secret))
        #expect(FileProbe.presence(at: instance.activeRunFile) == .absent)
    }
}

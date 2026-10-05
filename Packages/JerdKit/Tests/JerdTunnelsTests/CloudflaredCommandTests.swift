import Foundation
import JerdFoundation
import JerdProcess
import JerdTunnels
import Testing

@Suite struct CloudflaredCommandTests {
    private let instance = DataLayout(root: URL(fileURLWithPath: "/data root")).tunnels.instance(
        UUID(uuidString: "32394787-9B89-41AE-A065-57520475754A") ?? UUID())

    private func launch() throws -> TunnelLaunch {
        TunnelLaunch(
            runtime: TunnelRuntime(version: "2026.9.3", directory: URL(fileURLWithPath: "/runtimes/cloudflared")),
            registration: TunnelRegistration(name: "Preview", hostname: "preview.example.com", metricsPort: 20_242),
            token: try TunnelToken(TokenSamples.valid))
    }

    @Test func theConnectorCommandKeepsTheTokenOnlyInTheEnvironment() throws {
        let request = CloudflaredCommand.connector(try launch(), instance: instance)
        #expect(request.executable.path == "/runtimes/cloudflared/cloudflared")
        #expect(
            request.arguments == [
                "tunnel", "--config", "/data root/tunnels/instances/32394787-9B89-41AE-A065-57520475754A/config.yml",
                "--no-autoupdate", "--metrics", "127.0.0.1:20242", "--grace-period", "15s", "run",
            ])
        #expect(request.workingDirectory == instance.root)
        #expect(request.environment == ["HOME": instance.homeDirectory.path, "TUNNEL_TOKEN": TokenSamples.valid])
        #expect(request.redactedValues == [TokenSamples.valid, TokenSamples.secret])
        let arguments = request.arguments.joined(separator: " ")
        #expect(!arguments.contains(TokenSamples.valid))
        #expect(!arguments.contains(TokenSamples.secret))
    }

    @Test(arguments: [
        ("cloudflared version 2026.9.3 (built 2026-09-03-1200 UTC)", "2026.9.3"),
        ("cloudflared version 2026.9.30", "2026.9.30"),
        ("cloudflared version 2026.9.3", "2026.9.3"),
        ("warning: something\ncloudflared version 2025.11.1 (built today)\n", "2025.11.1"),
    ])
    func aVersionLineIsParsed(_ sample: (String, String)) {
        #expect(CloudflaredCommand.parseVersion(sample.0) == sample.1)
    }

    @Test(arguments: [
        "other version 2026.9.3", "xcloudflared version 2026.9.3", "cloudflared version 2026.9",
        "cloudflared version 2026.9.3-beta", " cloudflared version 2026.9.3", "",
    ])
    func otherOutputHasNoVersion(_ output: String) {
        #expect(CloudflaredCommand.parseVersion(output) == nil)
    }

    @Test func theEmptyConfigurationIsAnEmptyMap() {
        #expect(CloudflaredCommand.emptyConfiguration == Data("{}\n".utf8))
    }

    @Test(arguments: [
        (CommandResult(status: 1, output: ""), MetricsEndpoint.ListenerVerdict.none),
        (CommandResult(status: 0, output: "p7\nf9\nn127.0.0.1:20241\n"), .expected),
        (CommandResult(status: 0, output: "p7\nn*:20241\n"), .unexpected),
        (CommandResult(status: 0, output: "p7\nn[::1]:20241\n"), .unexpected),
        (CommandResult(status: 0, output: "p7\nn127.0.0.1:20241\nn127.0.0.1:8080\n"), .unexpected),
        (CommandResult(status: 0, output: "p7\nn127.0.0.1:20242\n"), .unexpected),
        (CommandResult(status: 1, output: "lsof: error"), .unexpected),
        (CommandResult(status: 0, output: "pnot-a-pid\nn127.0.0.1:20241\n"), .unexpected),
    ])
    func metricsListenersMustBeExactlyTheLoopbackPort(_ sample: (CommandResult, MetricsEndpoint.ListenerVerdict)) {
        #expect(MetricsEndpoint.listenerVerdict(sample.0, port: 20_241) == sample.1)
    }

    @Test func theMetricsPortMustHaveOnlyTheConnectorAsOwner() {
        #expect(MetricsEndpoint.ownersMatch(CommandResult(status: 0, output: "p7\n"), processID: 7))
        #expect(!MetricsEndpoint.ownersMatch(CommandResult(status: 0, output: "p7\np8\n"), processID: 7))
        #expect(!MetricsEndpoint.ownersMatch(CommandResult(status: 0, output: "p8\n"), processID: 7))
        #expect(!MetricsEndpoint.ownersMatch(CommandResult(status: 1, output: ""), processID: 7))
    }

    @Test func onlyAnExactHTTP200IsReady() {
        #expect(MetricsEndpoint.isReady(CommandResult(status: 0, output: "200")))
        for result in [
            CommandResult(status: 0, output: "503"), CommandResult(status: 7, output: "000"),
            CommandResult(status: 0, output: "2000"), CommandResult(status: 0, output: ""),
        ] {
            #expect(!MetricsEndpoint.isReady(result))
        }
    }

    @Test func readinessCommandsStayOnLoopbackAndIgnoreProxies() {
        let folder = URL(fileURLWithPath: "/tmp")
        let ready = MetricsEndpoint.readyRequest(port: 20_241, directory: folder)
        #expect(ready.executable.path == "/usr/bin/curl")
        #expect(ready.arguments.suffix(2) == ["--url", "http://127.0.0.1:20241/ready"])
        #expect(ready.arguments.contains("--noproxy"))
        #expect(
            MetricsEndpoint.listenersRequest(processID: 7, directory: folder).arguments == [
                "-nP", "-a", "-p", "7", "-iTCP", "-sTCP:LISTEN", "-Fn",
            ])
        #expect(
            MetricsEndpoint.ownersRequest(port: 20_241, directory: folder).arguments == [
                "-nP", "-a", "-iTCP:20241", "-sTCP:LISTEN", "-Fp",
            ])
    }
}

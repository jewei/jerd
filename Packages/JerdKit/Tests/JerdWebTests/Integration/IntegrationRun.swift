import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@testable import JerdWeb

/// Opt-in tests with real PHP and Caddy: `JERD_INTEGRATION=1`, `JERD_PHP_CLI`, `JERD_PHP_FPM`,
/// `JERD_CADDY`, and optionally `JERD_SECOND_PHP_CLI` and `JERD_SECOND_PHP_FPM`.
///
/// Every run uses an isolated CA, a temporary folder, and loopback ports above 1023. No trust
/// store, hosts file, or system service changes. Requests verify TLS with the run's CA only.
enum IntegrationRun {
    static let environment = ProcessInfo.processInfo.environment
    static let enabled = environment["JERD_INTEGRATION"] == "1"

    static func executable(_ name: String) throws -> URL {
        guard let path = environment[name], path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path)
        else {
            throw JerdError.unavailable("The opt-in test requires \(name) to name an executable at an absolute path.")
        }
        return URL(fileURLWithPath: path)
    }

    static func runtime(
        in folder: TemporaryDirectory, cli: String = "JERD_PHP_CLI", fpm: String = "JERD_PHP_FPM"
    )
        async throws -> DevelopmentRuntime
    {
        try await PHPRuntimeInspector().inspect(
            cli: try executable(cli), fpm: try executable(fpm), workDirectory: folder.path("inspection"))
    }

    static func caddy(in folder: TemporaryDirectory) async throws -> CaddyRuntime {
        try await CaddyRuntimeInspector().inspect(
            try executable("JERD_CADDY"), workDirectory: folder.path("inspection"))
    }

    /// A run layout in `folder` with a short socket folder below `/tmp`.
    static func layout(in folder: TemporaryDirectory, authority: LocalAuthority = .isolatedTest) -> RunLayout {
        RunLayout(
            environment: DataLayout(root: folder.path("data")).environment,
            socketDirectory: URL(fileURLWithPath: "/tmp/jerd-it-\(UUID().uuidString.prefix(8))", isDirectory: true),
            authority: authority)
    }

    /// One HTTPS request that verifies the server with the run's CA. Output: status, type, and body.
    static func request(
        _ host: String, _ path: String, port: UInt16, layout: RunLayout, extra: [String] = []
    ) async throws -> (code: String, body: Data) {
        let output = layout.environment.root.deletingLastPathComponent().appendingPathComponent("response-\(UUID())")
        let arguments =
            [
                "--noproxy", "*", "--silent", "--show-error", "--max-time", "8", "--cacert",
                layout.rootCertificateFile.path, "--resolve", "\(host):\(port):127.0.0.1", "--output", output.path,
                "--write-out", "%{http_code} %{content_type}",
            ] + extra + ["https://\(host):\(port)\(path)"]
        let result = try await CommandRunner().run(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/usr/bin/curl"), arguments: arguments,
                workingDirectory: layout.environment.root),
            timeout: .seconds(10))
        guard result.succeeded else { throw JerdError.processFailed("curl failed: \(result.diagnosticOutput)") }
        defer { try? FileManager.default.removeItem(at: output) }
        return (result.output, (try? Data(contentsOf: output)) ?? Data())
    }

    /// Two free loopback ports above 1023, for runs that bind their own listeners.
    static func freePorts() throws -> (https: UInt16, http: UInt16) {
        let first = try TestListeners.bind()
        let second = try TestListeners.bind()
        return (first.port, second.port)
    }
}

/// A supervisor wrapper that can stop the PHP masters of a run, to prove that one exit stops all.
actor ObservedProcesses: ProcessControlling {
    let real = ProcessSupervisor(ceiling: .forceful)
    private(set) var tokens: [(ProcessToken, isPHP: Bool)] = []

    func start(_ request: ProcessRequest, log: ProcessLogFile) async throws -> ProcessToken {
        let token = try await real.start(request, log: log)
        tokens.append((token, request.arguments.last == "-F"))
        return token
    }

    func state(of token: ProcessToken) async -> ProcessState { await real.state(of: token) }
    func processID(of token: ProcessToken) async -> pid_t? { await real.processID(of: token) }

    func waitForExit(of token: ProcessToken, timeout: Duration) async -> ProcessState {
        await real.waitForExit(of: token, timeout: timeout)
    }

    func stop(_ token: ProcessToken, policy: StopPolicy) async -> StopOutcome { await real.stop(token, policy: policy) }

    func stopAll(policy: StopPolicy) async -> [ProcessToken: StopOutcome] { await real.stopAll(policy: policy) }

    var phpCount: Int { tokens.filter(\.isPHP).count }

    /// Stops the PHP masters with SIGQUIT, as an outside crash would end them.
    func stopPHP() async {
        for (token, isPHP) in tokens where isPHP { _ = await real.stop(token, policy: .forceful(signal: SIGQUIT)) }
    }

    func allStopped() async -> Bool {
        for (token, _) in tokens where await real.state(of: token) == .running { return false }
        return true
    }
}

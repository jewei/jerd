import Foundation
import Security
import Testing
@testable import JerdCore

struct PHPTrustTests {
    @Test func onlyUnrestrictedServerTrustCanBecomeAPHPCA() throws {
        let approved = try CertificateTrustSettings.make(policy: .serverTLS, hostnames: ["site.test"])
        #expect(PHPTrustBundle.accepts(approved))
        var stored = approved
        stored[0]["kSecTrustSettingsPolicyName"] = "sslServer"
        #expect(PHPTrustBundle.accepts(stored))
        stored[0]["kSecTrustSettingsPolicyName"] = "sslClient"
        #expect(!PHPTrustBundle.accepts(stored))
        #expect(!PHPTrustBundle.accepts([]))
        #expect(!PHPTrustBundle.accepts(try CertificateTrustSettings.make(policy: .hostnames, hostnames: ["site.test"])))
        var denied = approved
        denied[0][kSecTrustSettingsResult as String] = NSNumber(value: SecTrustSettingsResult.deny.rawValue)
        #expect(!PHPTrustBundle.accepts(denied))
        var restricted = approved
        restricted[0][kSecTrustSettingsPolicyString as String] = "site.test"
        #expect(!PHPTrustBundle.accepts(restricted))
    }

    @Test func explicitCLITrustSettingsRemainEffective() throws {
        let root = try temporaryDirectory(" PHP trust café")
        defer { try? FileManager.default.removeItem(at: root) }
        let ca = root.appendingPathComponent("ca bundle.pem")
        let policy = try PHPConfigurationPolicy.cli(arguments: [], directory: root, environment: [:], caBundle: ca)
        #expect(policy.arguments == ["-c", root.appendingPathComponent("cli-local-tls.ini").path])
        let ini = try String(contentsOf: root.appendingPathComponent("cli-local-tls.ini"), encoding: .utf8)
        #expect(ini.contains("curl.cainfo = \"\(ca.path)\""))
        #expect(ini.contains("openssl.cafile = \"\(ca.path)\""))
        for key in ["SSL_CERT_FILE", "SSL_CERT_DIR", "CURL_CA_BUNDLE"] {
            _ = try PHPConfigurationPolicy.cli(arguments: [], directory: root, environment: [key: "/custom"], caBundle: ca)
            #expect(try !String(contentsOf: root.appendingPathComponent("cli.ini"), encoding: .utf8).contains("ca bundle.pem"))
            #expect(try String(contentsOf: root.appendingPathComponent("cli-local-tls.ini"), encoding: .utf8) == ini)
        }
        for arguments in [["-n"], ["-c", "/custom/php.ini"]] {
            #expect(try PHPConfigurationPolicy.cli(arguments: arguments, directory: root, environment: [:], caBundle: ca).arguments.isEmpty)
        }
        #expect(throws: JerdError.self) {
            try PHPConfigurationPolicy.trustINI(root.appendingPathComponent("${UNTRUSTED}.pem"))
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_INTEGRATION"] == "1",
                   "Select independent PHP and Caddy binaries for the PHP TLS client test."), arguments: [false, true])
    func cliAndFPMVerifyLocalHTTPSOnlyWithApprovedTrust(approved: Bool) async throws {
        let environment = ProcessInfo.processInfo.environment
        let root = try temporaryDirectory(" PHP TLS café")
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID()
        let paths = EnginePaths(root: root.appendingPathComponent("environment"),
            socketDirectory: URL(fileURLWithPath: "/tmp/jerd-client-\(UUID().uuidString.prefix(12))"), installationID: identity)
        try PrivateFiles.directory(paths.root)
        try PrivateFiles.write(Data(identity.uuidString.utf8), to: paths.root.appendingPathComponent("installation-id"))
        let provider = DevelopmentRuntimeProvider()
        let runtime = try await provider.inspectPHP(cli: URL(fileURLWithPath: try #require(environment["JERD_PHP_CLI"])),
            fpm: URL(fileURLWithPath: try #require(environment["JERD_PHP_FPM"])), workDirectory: root)
        let caddy = try await provider.inspectCaddy(binary: URL(fileURLWithPath: try #require(environment["JERD_CADDY"])), workDirectory: root)
        let client = root.appendingPathComponent("client"), peer = root.appendingPathComponent("peer")
        try PrivateFiles.directory(client)
        try PrivateFiles.directory(peer)
        try PrivateFiles.write(Data("peer-ok".utf8), to: peer.appendingPathComponent("peer.txt"))
        let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
        defer { sockets.close() }
        let ports = try sockets.ports()
        let script = client.appendingPathComponent("index.php")
        let code = """
        <?php
        $curl = curl_init('https://peer.test:\(ports.https)/peer.txt');
        curl_setopt_array($curl, [CURLOPT_RETURNTRANSFER => true, CURLOPT_NOPROXY => '*',
            CURLOPT_RESOLVE => ['peer.test:\(ports.https):127.0.0.1'], CURLOPT_TIMEOUT => 3]);
        $curlBody = curl_exec($curl);
        $context = stream_context_create(['ssl' => ['peer_name' => 'peer.test'],
            'http' => ['header' => "Host: peer.test\\r\\n", 'timeout' => 3]]);
        $streamBody = @file_get_contents('https://127.0.0.1:\(ports.https)/peer.txt', false, $context);
        echo json_encode(['curl' => $curlBody, 'stream' => $streamBody, 'error' => curl_error($curl)]);
        """
        try PrivateFiles.write(Data(code.utf8), to: script)
        // Approval is injected only for this isolated CA; no trust store changes.
        let trust = PHPTrustBundle(isTrusted: { _ in approved })
        let engine = ServingEngine(phpTrust: trust)
        do {
            try await engine.start(sites: [SiteRuntime(site: makeSite(client, hostname: "client.test"), runtime: runtime),
                                          SiteRuntime(site: makeSite(peer, hostname: "peer.test"), runtime: runtime)],
                caddy: caddy, paths: paths, httpsPort: ports.https, httpPort: ports.http, listeningSockets: sockets)
            #expect(try PHPTrustBundle().forCLI(applicationDirectory: root) == nil)
            let ca = try trust.forCLI(applicationDirectory: root)
            #expect((ca != nil) == approved)
            if let ca {
                let roots = try Data(contentsOf: URL(fileURLWithPath: "/etc/ssl/cert.pem"))
                #expect(try Data(contentsOf: ca).starts(with: roots))
            }
            let policy = try PHPConfigurationPolicy.cli(arguments: [script.path], directory: root.appendingPathComponent("runtimes/configuration"),
                environment: [:], caBundle: ca)
            let cli = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: runtime.cliPath),
                arguments: policy.arguments + [script.path], directory: root, environment: policy.environment), timeout: .seconds(8))
            let fpm = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: ["--noproxy", "*", "--silent", "--show-error", "--fail", "--max-time", "8",
                    "--cacert", paths.rootCertificate.path, "--resolve", "client.test:\(ports.https):127.0.0.1",
                    "https://client.test:\(ports.https)/"], directory: root), timeout: .seconds(10))
            for result in [cli, fpm] {
                #expect(result.status == 0, "\(result.diagnosticOutput)")
                let body = try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
                for key in ["curl", "stream"] {
                    if approved { #expect(body[key] as? String == "peer-ok", "\(result.output)") }
                    else { #expect(body[key] as? Bool == false, "\(result.output)") }
                }
            }
            if approved {
                let override = try PHPConfigurationPolicy.cli(arguments: ["-n", script.path], directory: root, environment: [:], caBundle: ca)
                let result = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: runtime.cliPath),
                    arguments: override.arguments + ["-n", script.path], directory: root, environment: override.environment), timeout: .seconds(8))
                let body = try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
                #expect(body["curl"] as? Bool == false && body["stream"] as? Bool == false)
            }
            await engine.stop()
        } catch { await engine.stop(); throw error }
    }
}

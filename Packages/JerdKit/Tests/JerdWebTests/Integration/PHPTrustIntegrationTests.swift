import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

@Suite(.enabled(if: IntegrationRun.enabled, "Set JERD_INTEGRATION=1 and select PHP CLI, PHP-FPM, and Caddy."))
struct PHPTrustIntegrationTests {
    /// The trust answer is injected for this isolated CA only; no trust store changes.
    @Test(arguments: [false, true])
    func phpReachesALocalSiteOnlyWithApprovedTrust(approved: Bool) async throws {
        let folder = try TemporaryDirectory(" PHP TLS café")
        defer { folder.remove() }
        let data = DataLayout(root: folder.path("data"))
        let installationID = try InstallationIdentity(environment: data.environment).readOrCreate()
        let layout = RunLayout(
            environment: data.environment,
            socketDirectory: URL(fileURLWithPath: "/tmp/jerd-it-\(UUID().uuidString.prefix(8))", isDirectory: true),
            authority: .installation(installationID))
        let listeners = try TestListeners()
        defer { listeners.close() }
        let port = listeners.httpsPort
        try folder.file("peer/peer.txt", "peer-ok")
        let script = try folder.file("client/index.php", Self.client(port: port))
        let runtime = try await IntegrationRun.runtime(in: folder)
        let plan = ServingPlan(
            sites: [
                PlannedSite(site: Samples.site(folder.path("client"), hostname: "client.test"), runtime: runtime),
                PlannedSite(site: Samples.site(folder.path("peer"), hostname: "peer.test"), runtime: runtime),
            ], caddy: try await IntegrationRun.caddy(in: folder))
        let builder = PHPCABundleBuilder(trust: FixedTrust(trusted: approved))
        let engine = EngineRunner(services: EngineServices(caBundle: builder))
        _ = try await engine.start(
            plan, layout: layout,
            binding: ListenerBinding(httpsPort: port, httpPort: listeners.httpPort, inherited: true),
            listeners: listeners.inherited)
        do {
            #expect(try PHPCABundleBuilder().prepareForCLI(layout: data) == nil)
            let bundle = try builder.prepareForCLI(layout: data)
            #expect((bundle != nil) == approved)
            if let bundle {
                #expect(
                    try Data(contentsOf: bundle).starts(with: try Data(contentsOf: PHPCABundleBuilder.systemRootsFile)))
            }
            let ini = try folder.file("cli.ini", try PHPIniPolicy.cliFile(caBundle: bundle))
            let cli = try await CommandRunner().run(
                ProcessRequest(
                    executable: URL(fileURLWithPath: runtime.cliPath), arguments: ["-c", ini.path, script.path],
                    workingDirectory: folder.url, environment: ["PHP_INI_SCAN_DIR": try folder.folder("empty").path]),
                timeout: .seconds(10))
            let fpm = try await IntegrationRun.request("client.test", "/", port: port, layout: layout)
            for output in [Data(cli.output.utf8), fpm.body] {
                let body = try #require(try JSONSerialization.jsonObject(with: output) as? [String: Any])
                for key in ["curl", "stream"] {
                    if approved {
                        #expect(body[key] as? String == "peer-ok", "\(body)")
                    } else {
                        #expect(body[key] as? Bool == false, "\(body)")
                    }
                }
            }
        } catch {
            await engine.stop()
            throw error
        }
        await engine.stop()
    }

    static func client(port: UInt16) -> String {
        """
        <?php
        $curl = curl_init('https://peer.test:\(port)/peer.txt');
        curl_setopt_array($curl, [CURLOPT_RETURNTRANSFER => true, CURLOPT_NOPROXY => '*',
            CURLOPT_RESOLVE => ['peer.test:\(port):127.0.0.1'], CURLOPT_TIMEOUT => 3]);
        $curlBody = curl_exec($curl);
        $context = stream_context_create(['ssl' => ['peer_name' => 'peer.test'],
            'http' => ['header' => "Host: peer.test\\r\\n", 'timeout' => 3]]);
        $streamBody = @file_get_contents('https://127.0.0.1:\(port)/peer.txt', false, $context);
        echo json_encode(['curl' => $curlBody, 'stream' => $streamBody]);
        """
    }
}

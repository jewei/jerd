import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

@Suite(.enabled(if: IntegrationRun.enabled, "Set JERD_INTEGRATION=1 and select PHP CLI, PHP-FPM, and Caddy."))
struct ServingIntegrationTests {
    @Test(arguments: [false, true])
    func realPHPAnswersOverVerifiedTLSAndTheRulesHold(inherited: Bool) async throws {
        let folder = try TemporaryDirectory(" TLS café 项目")
        defer { folder.remove() }
        let project = folder.path("project café space")
        try FileManager.default.copyItem(at: try Fixture.url("site"), to: project)
        for (name, text) in [
            (".env", "jerd-secret"), (".git/config", "jerd-secret"), ("source.PHP", "<?php echo 'leak';"),
            ("index.php.bak", "<?php echo 'leak';"), ("hello.txt", "static-ok"),
            (".well-known/security.txt", "Contact: mailto:security@example.test"), (".well-known/.hidden", "hidden"),
            (".well-known/probe.php", "<?php echo 'leak';"),
        ] {
            try FileManager.default.createDirectory(
                at: project.appendingPathComponent(name).deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: project.appendingPathComponent(name))
        }
        let runtime = try await IntegrationRun.runtime(in: folder)
        let caddy = try await IntegrationRun.caddy(in: folder)
        let site = Samples.site(project, hostname: "jerd-smoke.test")
        let plan = ServingPlan(sites: [PlannedSite(site: site, runtime: runtime)], caddy: caddy)
        let layout = IntegrationRun.layout(in: folder, authority: inherited ? .installation(UUID()) : .isolatedTest)
        let listeners = inherited ? try TestListeners() : nil
        defer { listeners?.close() }
        let ports = try listeners.map { ($0.httpsPort, $0.httpPort) } ?? IntegrationRun.freePorts()
        let binding = ListenerBinding(httpsPort: ports.0, httpPort: ports.1, inherited: inherited)
        let processes = ObservedProcesses()
        let engine = EngineRunner(services: EngineServices(processes: processes))
        do {
            let run = try await engine.start(plan, layout: layout, binding: binding, listeners: listeners?.inherited)
            try await checkResponses(site.hostname, runtime: runtime, layout: layout, binding: binding)
            await processes.stopPHP()
            let failure = await engine.waitForFailure(of: run)
            let state = await engine.state
            #expect(failure == EngineRunner.exitMessage, "\(String(describing: failure)) \(state)")
            #expect(await processes.allStopped())
            #expect(isAbsent(layout.socketDirectory))
        } catch {
            await engine.stop()
            throw error
        }
    }

    private func checkResponses(
        _ host: String, runtime: DevelopmentRuntime, layout: RunLayout, binding: ListenerBinding
    ) async throws {
        let port = binding.httpsPort
        let proof = try await IntegrationRun.request(host, "/", port: port, layout: layout)
        let body = try #require(try JSONSerialization.jsonObject(with: proof.body) as? [String: Any])
        #expect(body["proof"] as? String == "jerd-php-executed" && body["sapi"] as? String == "fpm-fcgi")
        #expect(body["version"] as? String == runtime.version && body["answer"] as? Int == 42)
        #expect(
            try await IntegrationRun.request(host, "/hello.txt", port: port, layout: layout).body
                == Data("static-ok".utf8))
        let wellKnown = try await IntegrationRun.request(host, "/.well-known/security.txt", port: port, layout: layout)
        #expect(
            wellKnown.code.hasPrefix("200 ") && wellKnown.body == Data("Contact: mailto:security@example.test".utf8))
        for path in [
            "/.env", "/.git/config", "/%2eenv", "/source.PHP", "/index.php.bak", "/.well-known/.hidden",
            "/.well-known/probe.php", "/.well-known/missing.txt",
        ] {
            let denied = try await IntegrationRun.request(host, path, port: port, layout: layout)
            #expect(denied.code.hasPrefix("404"), "Unexpected response for \(path): \(denied.code)")
            #expect(!String(decoding: denied.body, as: UTF8.self).contains("leak"))
        }
        let unknown = try await IntegrationRun.request(
            host, "/", port: port, layout: layout, extra: ["--header", "Host: unknown.test"])
        #expect(unknown.code.hasPrefix("421"))
        let redirect = try await CommandRunner().run(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: [
                    "--noproxy", "*", "--silent", "--max-time", "4", "--dump-header", "-", "--output", "/dev/null",
                    "--header", "Host: \(host)", "http://127.0.0.1:\(binding.httpPort)/hello.txt",
                ], workingDirectory: layout.environment.root))
        #expect(redirect.output.contains("308"))
        #expect(redirect.output.lowercased().contains("location: https://\(host):\(port)/hello.txt"))
    }

    @Test func publicStorageServesAssetsButNeverPrivateFilesOrPHP() async throws {
        let folder = try TemporaryDirectory(" public storage")
        defer { folder.remove() }
        let project = try folder.folder("laravel")
        let publicRoot = try folder.folder("laravel/public")
        let storage = try folder.folder("laravel/storage/app/public")
        let plain = try folder.folder("project-root")
        try folder.file("laravel/public/index.php", "<?php echo 'front-controller';")
        try folder.file("project-root/index.php", "<?php echo 'other-site';")
        try folder.file("project-root/storage/logs/laravel.log", "private-log-must-not-leak")
        try folder.file("laravel/storage/app/public/.env", "private-env-must-not-leak")
        try folder.file(
            "laravel/storage/app/public/directory/index.php", "<?php echo 'directory-index-must-not-execute';")
        let asset = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46, 0xFF, 0xD9])
        try FileManager.default.createDirectory(
            at: storage.appendingPathComponent("112"), withIntermediateDirectories: true)
        try asset.write(to: storage.appendingPathComponent("112/amazon-us.jpg"))
        let scripts = ["upload.php", "upload.PHP", "upload.php.bak", "upload.phtml", "upload.phar"]
        for name in scripts {
            try folder.file("laravel/storage/app/public/\(name)", "<?php echo 'upload-must-not-execute';")
        }
        try FileManager.default.createSymbolicLink(
            at: publicRoot.appendingPathComponent("storage"), withDestinationURL: storage)
        let runtime = try await IntegrationRun.runtime(in: folder)
        let publicSite = Samples.site(project, hostname: "public-storage.test", documentRoot: publicRoot)
        let privateSite = Samples.site(plain, hostname: "private-storage.test")
        let plan = ServingPlan(
            sites: [PlannedSite(site: publicSite, runtime: runtime), PlannedSite(site: privateSite, runtime: runtime)],
            caddy: try await IntegrationRun.caddy(in: folder))
        let layout = IntegrationRun.layout(in: folder)
        let listeners = try TestListeners()
        defer { listeners.close() }
        let engine = EngineRunner()
        _ = try await engine.start(
            plan, layout: layout,
            binding: ListenerBinding(httpsPort: listeners.httpsPort, httpPort: listeners.httpPort, inherited: true),
            listeners: listeners.inherited)
        do {
            try await checkStorage(
                publicSite.hostname, privateSite.hostname, port: listeners.httpsPort, layout: layout, asset: asset,
                scripts: scripts)
        } catch {
            await engine.stop()
            throw error
        }
        await engine.stop()
    }

    private func checkStorage(
        _ publicHost: String, _ privateHost: String, port: UInt16, layout: RunLayout, asset: Data, scripts: [String]
    ) async throws {
        let image = try await IntegrationRun.request(
            publicHost, "/storage/112/amazon-us.jpg", port: port, layout: layout)
        #expect(image.code == "200 image/jpeg" && image.body == asset)
        #expect(
            try await IntegrationRun.request(publicHost, "/", port: port, layout: layout).body
                == Data("front-controller".utf8))
        for path in ["/storage/.env", "/storage/upload.php/extra", "/storage/directory", "/storage/directory/"]
            + scripts.map({ "/storage/\($0)" })
        {
            let denied = try await IntegrationRun.request(publicHost, path, port: port, layout: layout)
            #expect(
                denied.code.hasPrefix("404 ") && denied.body.isEmpty, "Unexpected response for \(path): \(denied.code)")
        }
        let privateLog = try await IntegrationRun.request(
            privateHost, "/storage/logs/laravel.log", port: port, layout: layout)
        #expect(privateLog.code.hasPrefix("404 ") && privateLog.body.isEmpty)
    }
}

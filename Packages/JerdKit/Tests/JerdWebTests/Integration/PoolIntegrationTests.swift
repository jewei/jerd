import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite(.enabled(if: IntegrationRun.enabled, "Set JERD_WEB_INTEGRATION=1 and select PHP CLI, PHP-FPM, and Caddy."))
struct PoolIntegrationTests {
    @Test(arguments: [false, true])
    func sitesUseTheirOwnRootsAndPoolsAndOneExitStopsAll(separatePools: Bool) async throws {
        let folder = try TemporaryDirectory(" multi TLS")
        defer { folder.remove() }
        let runtime = try await IntegrationRun.runtime(in: folder)
        var second = runtime
        if separatePools {
            if IntegrationRun.environment["JERD_SECOND_PHP_CLI"] != nil {
                second = try await IntegrationRun.runtime(
                    in: folder, cli: "JERD_SECOND_PHP_CLI", fpm: "JERD_SECOND_PHP_FPM")
            } else {
                second.id = UUID()
            }
        }
        var sites: [Site] = []
        for name in ["first", "second"] {
            try folder.file("\(name)/index.php", "<?php echo '\(name)-php-' . (6 * 7);")
            try folder.file("\(name)/version.php", "<?php echo PHP_VERSION;")
            try folder.file("\(name)/hello.txt", "\(name)-static")
            sites.append(Samples.site(folder.path(name), hostname: "\(name).test"))
        }
        let plan = ServingPlan(
            sites: [PlannedSite(site: sites[0], runtime: runtime), PlannedSite(site: sites[1], runtime: second)],
            caddy: try await IntegrationRun.caddy(in: folder))
        let layout = IntegrationRun.layout(in: folder)
        let listeners = try TestListeners()
        defer { listeners.close() }
        let processes = ObservedProcesses()
        let engine = EngineRunner(services: EngineServices(processes: processes))
        let binding = ListenerBinding(httpsPort: listeners.httpsPort, httpPort: listeners.httpPort, inherited: true)
        let run = try await engine.start(plan, layout: layout, binding: binding, listeners: listeners.inherited)
        do {
            #expect(await processes.phpCount == (separatePools ? 2 : 1))
            let port = listeners.httpsPort
            async let first = IntegrationRun.request("first.test", "/", port: port, layout: layout)
            async let other = IntegrationRun.request("second.test", "/", port: port, layout: layout)
            let answers = try await (first, other)
            #expect(answers.0.body == Data("first-php-42".utf8) && answers.1.body == Data("second-php-42".utf8))
            #expect(
                try await IntegrationRun.request("first.test", "/version.php", port: port, layout: layout).body
                    == Data(runtime.version.utf8))
            #expect(
                try await IntegrationRun.request("second.test", "/version.php", port: port, layout: layout).body
                    == Data(second.version.utf8))
            #expect(
                try await IntegrationRun.request("second.test", "/hello.txt", port: port, layout: layout).body
                    == Data("second-static".utf8))
        } catch {
            await engine.stop()
            throw error
        }
        await processes.stopPHP()
        #expect(await engine.waitForFailure(of: run) == EngineRunner.exitMessage)
        #expect(await processes.allStopped())
    }

    @Test func theFPMAndCLIPoliciesDifferOnlyWhereTheyShould() async throws {
        let folder = try TemporaryDirectory(" policy")
        defer { folder.remove() }
        let code = """
            $keys = ['date.timezone', 'expose_php', 'log_errors', 'memory_limit', 'max_execution_time'];
            $settings = []; foreach ($keys as $key) { $settings[$key] = ini_get($key); }
            echo json_encode($settings);
            """
        try folder.file("site/policy.php", "<?php " + code)
        let runtime = try await IntegrationRun.runtime(in: folder)
        let plan = ServingPlan(
            sites: [PlannedSite(site: Samples.site(folder.path("site"), hostname: "policy.test"), runtime: runtime)],
            caddy: try await IntegrationRun.caddy(in: folder))
        let layout = IntegrationRun.layout(in: folder)
        let listeners = try TestListeners()
        defer { listeners.close() }
        let engine = EngineRunner()
        _ = try await engine.start(
            plan, layout: layout,
            binding: ListenerBinding(httpsPort: listeners.httpsPort, httpPort: listeners.httpPort, inherited: true),
            listeners: listeners.inherited)
        let fpm = try await IntegrationRun.request(
            "policy.test", "/policy.php", port: listeners.httpsPort, layout: layout)
        await engine.stop()
        let ini = try folder.file("cli.ini", try PHPIniPolicy.cliFile(caBundle: nil))
        let cli = try await CommandRunner().run(
            ProcessRequest(
                executable: URL(fileURLWithPath: runtime.cliPath), arguments: ["-c", ini.path, "-r", code],
                workingDirectory: folder.url, environment: ["PHP_INI_SCAN_DIR": try folder.folder("empty").path]))
        let web = try #require(try JSONSerialization.jsonObject(with: fpm.body) as? [String: String])
        let terminal = try #require(try JSONSerialization.jsonObject(with: Data(cli.output.utf8)) as? [String: String])
        for key in ["date.timezone", "expose_php", "log_errors"] { #expect(web[key] == terminal[key]) }
        #expect(web["date.timezone"] == "UTC")
        #expect(web["memory_limit"] == "256M" && terminal["memory_limit"] == "-1")
        #expect(web["max_execution_time"] == "30" && terminal["max_execution_time"] == "0")
    }
}

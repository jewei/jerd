import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite struct RuntimeInspectorTests {
    let cli = URL(fileURLWithPath: "/local/php")
    let fpm = URL(fileURLWithPath: "/local/php-fpm")

    func inspect(_ script: InspectionScript, in folder: TemporaryDirectory) async throws -> DevelopmentRuntime {
        let when = Date(timeIntervalSinceReferenceDate: 42)
        return try await PHPRuntimeInspector(commands: script.runner(), now: { when })
            .inspect(cli: cli, fpm: fpm, workDirectory: folder.path("work"))
    }

    @Test func aMatchingPairBecomesARecordWithSortedExtensions() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let runner = InspectionScript().runner()
        let runtime = try await PHPRuntimeInspector(commands: runner).inspect(
            cli: cli, fpm: fpm, workDirectory: folder.path("work"))
        #expect(runtime.version == "8.4.0" && runtime.cliPath == "/local/php" && runtime.fpmPath == "/local/php-fpm")
        #expect(runtime.cliExtensions == ["Core", "json"] && runtime.fpmExtensions == ["Core", "json"])
        #expect(runtime.architectures == [.current])
        #expect(mode(folder.path("work/empty-ini")) == 0o700)
        let php = runner.requests.filter { $0.executable.lastPathComponent != "lipo" }
        #expect(php.allSatisfy { $0.arguments.first == "-n" })
        #expect(php.allSatisfy { $0.environment == ["PHP_INI_SCAN_DIR": folder.path("work/empty-ini").path] })
    }

    @Test(arguments: [
        (
            InspectionScript(fpmVersion: "8.3.0"),
            "PHP CLI and PHP-FPM must report the same full version and the correct SAPI."
        ),
        (InspectionScript(sapi: "cgi-fcgi"), "Select a PHP CLI executable."),
        (InspectionScript(modules: "[Zend Modules]\n"), "PHP-FPM returned no extension list."),
    ])
    func mismatchedPairsAreRefused(_ script: InspectionScript, _ message: String) async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        await #expect(throws: JerdError.invalid(message)) { try await inspect(script, in: folder) }
    }

    @Test func aForeignArchitectureOrAFailedCommandIsRefused() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let other = CPUArchitecture.current == .arm64 ? "x86_64" : "arm64"
        await #expect(
            throws: JerdError.unavailable("Both PHP executables must contain the current process architecture.")
        ) {
            try await inspect(InspectionScript(architectures: "\(other) arm64e"), in: folder)
        }
        await #expect(throws: JerdError.processFailed("Runtime inspection failed: inspection failed")) {
            try await inspect(InspectionScript(failing: "-m"), in: folder)
        }
    }

    @Test(arguments: ["/Applications/Herd.app/bin/php", "/Users/u/Library/herd/bin/php"])
    func herdBinariesAreRefused(_ path: String) async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        await #expect(throws: JerdError.invalid("Do not select Herd binaries. Use an independent local build.")) {
            try await PHPRuntimeInspector(commands: InspectionScript().runner()).inspect(
                cli: URL(fileURLWithPath: path), fpm: fpm, workDirectory: folder.path("work"))
        }
    }

    @Test func caddyNeedsTheCurrentArchitectureAndAVersion2Release() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let binary = URL(fileURLWithPath: "/local/caddy")
        let caddy = try await CaddyRuntimeInspector(commands: InspectionScript().runner()).inspect(
            binary, workDirectory: folder.url)
        #expect(caddy == CaddyRuntime(path: "/local/caddy", version: "v2.11.4 h1:abc=", architectures: [.current]))
        await #expect(throws: JerdError.invalid("Select a Caddy 2 executable with a release version.")) {
            try await CaddyRuntimeInspector(commands: InspectionScript(caddyVersion: "v1.0.0").runner()).inspect(
                binary, workDirectory: folder.url)
        }
    }

    @Test func driftChecksCompareVersionsAndExtensions() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let check = RuntimeDriftCheck(commands: InspectionScript().runner())
        try await check.requireUnchanged(Samples.runtime(), workDirectory: folder.url)
        await #expect(
            throws: JerdError.unavailable("PHP changed since inspection. Inspect and select the runtime again.")
        ) {
            try await check.requireUnchanged(Samples.runtime(extensions: ["Core"]), workDirectory: folder.url)
        }
        await #expect(throws: JerdError.unavailable("Caddy changed since inspection. Select it again.")) {
            try await check.requireUnchanged(Samples.caddy(version: "v2.10.0"), workDirectory: folder.url)
        }
    }

    @Test func oneRuntimeIDWithTwoRecordsIsRefused() throws {
        let runtime = Samples.runtime()
        let changed = Samples.runtime(id: runtime.id, version: "9.0.0")
        let sites = [
            Samples.site(URL(fileURLWithPath: "/a"), hostname: "a.test"),
            Samples.site(URL(fileURLWithPath: "/b"), hostname: "b.test"),
        ]
        let same = ServingPlan(sites: sites.map { PlannedSite(site: $0, runtime: runtime) }, caddy: Samples.caddy())
        #expect(try RuntimeDriftCheck.distinctRuntimes(of: same).map(\.id) == [runtime.id])
        let conflict = ServingPlan(
            sites: [PlannedSite(site: sites[0], runtime: runtime), PlannedSite(site: sites[1], runtime: changed)],
            caddy: Samples.caddy())
        #expect(throws: JerdError.invalid("A PHP runtime ID has conflicting settings.")) {
            try RuntimeDriftCheck.distinctRuntimes(of: conflict)
        }
    }

    @Test func moduleListsKeepOnlyThePHPSection() {
        #expect(
            PHPModuleList.parse("[PHP Modules]\n  json\nCore\njson\n\n[Zend Modules]\nZend OPcache\n") == [
                "Core", "json",
            ])
        #expect(PHPModuleList.parse("Core\n") == [])
    }
}

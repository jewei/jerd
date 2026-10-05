import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct VersionPatternTests {
    @Test(arguments: [
        ("cloudflared version 2026.9.3 (built today)", true), ("cloudflared version 2026.9.30", false),
        ("other version 2026.9.3", false), ("cloudflared version 2026.9.3", true),
        ("x cloudflared version 2026.9.3", false),
    ])
    func cloudflaredOutputMustNameTheProductAndExactVersion(_ output: String, _ accepted: Bool) {
        #expect((VersionPattern.cloudflared.version(in: output, expected: "2026.9.3") != nil) == accepted)
    }

    @Test(arguments: [
        ("mysqld  Ver 8.4.11 for macos15 on arm64", true), ("Ver 8.4.110", false), ("Ver 18.4.11", false),
        ("Ver 8.4.11.1", false), ("Mailpit v8.4.11 darwin", true),
    ])
    func boundedVersionIsNotPartOfALongerNumber(_ output: String, _ accepted: Bool) {
        #expect((VersionPattern.bounded.version(in: output, expected: "8.4.11") != nil) == accepted)
    }

    @Test func postgresReportsItsEngineVersion() {
        let output = "postgres (PostgreSQL) 18.6"
        #expect(VersionPattern.postgresEngine.version(in: output, expected: "2.9.6") == "18.6")
        #expect(VersionPattern.postgresEngine.version(in: "postgres 18.6", expected: "2.9.6") == nil)
    }

    @Test func redisMustReportTheReleaseVersion() {
        let output = "Redis server v=8.8.3 sha=00000000:0 malloc=libc bits=64 build=1"
        #expect(VersionPattern.redis.version(in: output, expected: "8.8.3") == "8.8.3")
        #expect(VersionPattern.redis.version(in: output, expected: "8.8.2") == nil)
        #expect(
            VersionPattern.redis.mismatch(title: "Redis") == .invalid("The runtime version does not match the release.")
        )
    }

    @Test func phpCLIAndFPMMustReportTheirServerAPI() {
        let cli = "PHP 8.5.11 (cli) (built: Oct  1 2026) (NTS)"
        let fpm = "PHP 8.5.11 (fpm-fcgi) (built: Oct  1 2026)"
        #expect(VersionPattern.php(sapi: "cli").version(in: cli, expected: "8.5.11") == "8.5.11")
        #expect(VersionPattern.php(sapi: "cli").version(in: fpm, expected: "8.5.11") == nil)
        #expect(VersionPattern.php(sapi: "fpm-fcgi").version(in: fpm, expected: "8.5.11") == "8.5.11")
        #expect(VersionPattern.php(sapi: "cli").version(in: cli, expected: "8.5.1") == nil)
    }

    @Test func caddyFirstWordIsTheTaggedVersion() {
        let output = "v2.11.4 h1:abc="
        #expect(VersionPattern.caddy.version(in: output, expected: "2.11.4") == "2.11.4")
        #expect(VersionPattern.caddy.version(in: "v2.11.40", expected: "2.11.4") == nil)
    }

    @Test func probesFollowTheKindTable() throws {
        let php = try VersionProbe.probes(for: .php, version: "8.4.26")
        #expect(php.map(\.executable.string) == ["php-native-8.4", "php-native-fpm-8.4"])
        #expect(try VersionProbe.probes(for: .composer, version: "2.10.3").first?.runsWithPHP == true)
        #expect(
            try VersionProbe.probes(for: .mailpit, version: "1.31.3").first?.arguments
                == ["version", "--no-release-check"])
        for kind in RuntimeKind.allCases {
            #expect(try !VersionProbe.probes(for: kind, version: "1.2.3").isEmpty)
        }
    }

    @Test func phpBranchComesFromTheVersionNotAFixedName() throws {
        #expect(try PHPPreparer.executables(version: "8.6.0") == ("php-native-8.6", "php-native-fpm-8.6"))
    }
}

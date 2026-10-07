import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct PreparerRuleTests {
    private func path(_ text: String) throws -> RelativePath { try #require(RelativePath(text)) }

    @Test(arguments: [
        ("bin/mysqld", true), ("bin/mysql", true), ("bin/mysqlsh", false), ("bin/libprotobuf.dylib", true),
        ("lib/libssl.dylib", true), ("lib/libmysqlclient.a", false), ("share/english/errmsg.sys", true),
        ("LICENSE", true), ("README", true), ("docs/INFO_SRC", false), ("include/mysql.h", false),
    ])
    func mysqlKeepsTheServerClientsLibrariesAndSharedData(_ text: String, _ kept: Bool) throws {
        #expect(MySQLTarPreparer.selects(try path(text)) == kept)
    }

    @Test(arguments: [
        ("bin/postgres", true), ("lib/libpq.5.dylib", true), ("lib/libpgcommon.a", false),
        ("lib/postgresql/plpython3.dylib", false), ("lib/postgresql/hstore_plpython3.dylib", false),
        ("lib/postgresql/plpgsql.dylib", true), ("share/postgresql/extension/plpython3u.control", false),
        ("share/postgresql/extension/jsonb_plpython3u--1.0.sql", false),
        ("share/postgresql/extension/plpgsql.control", true),
    ])
    func postgresLeavesOutStaticLibrariesAndPLPython(_ text: String, _ kept: Bool) throws {
        #expect(PostgresAppPreparer.selects(try path(text)) == kept)
    }

    @Test(arguments: [
        ("src/server.c", true), ("modules/vector-sets/vset.c", true), ("modules/redisjson/x.c", false),
        ("deps/jemalloc/COPYING", true),
    ])
    func redisBuildsWithoutThirdPartyModules(_ text: String, _ kept: Bool) throws {
        #expect(RedisSourceBuilder.selectsSource(try path(text)) == kept)
    }

    @Test func redisUsesAtMostFourJobsWithoutTLS() {
        #expect(
            RedisSourceBuilder.makeArguments(processors: 12)
                == ["-j4", "MALLOC=libc", "BUILD_TLS=no", "redis-server", "redis-cli"])
        #expect(RedisSourceBuilder.makeArguments(processors: 2).first == "-j2")
        #expect(RedisSourceBuilder.makeArguments(processors: 0).first == "-j1")
    }

    @Test func laravelProjectFileHasTheExactCompactForm() throws {
        let text = String(decoding: try LaravelComposerResolver.projectFile(version: "5.32.0"), as: UTF8.self)
        #expect(
            text
                == #"{"config":{"allow-plugins":false,"notify-on-install":false,"preferred-install":"dist","secure-http":true},"require":{"laravel\/installer":"5.32.0"}}"#
        )
        #expect(LaravelComposerResolver.composerArguments(locked: false).first == "update")
        #expect(LaravelComposerResolver.composerArguments(locked: true).first == "install")
        #expect(LaravelComposerResolver.composerArguments(locked: true).contains("--no-plugins"))
    }

    @Test func postgresAppRequirementPinsItsTeamAndIdentifier() {
        let arguments = CodeRequirement.postgresApp.verifyArguments(for: "/Volumes/P/Postgres.app")
        #expect(arguments.prefix(4) == ["--verify", "--deep", "--strict", "-R"])
        #expect(arguments[4].hasPrefix("=identifier \"com.postgresapp.Postgres2\" and anchor apple generic"))
        #expect(arguments[4].hasSuffix("certificate leaf[subject.OU] = \"ZF84SJ5A3G\""))
    }

    @Test(arguments: [RuntimeKind.composer, .rustfs, .cloudflared])
    func licensesWithoutAnArchiveCopyArePinned(_ kind: RuntimeKind) throws {
        let license = try #require(try PinnedLicense.of(kind))
        #expect(license.url.host == "raw.githubusercontent.com")
        #expect(FileDigest.isSHA256Hex(license.sha256))
        #expect(try PinnedLicense.of(.php) == nil)
    }

    @Test func pinnedLicenseWithTheReviewedTextIsWrittenPrivately() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let license = try #require(try PinnedLicense.of(.cloudflared))
        let fetcher = FakeFetcher([license.url: try Fixture.data("Licenses/cloudflared-LICENSE")])
        try await license.fetch(to: folder.path("LICENSE"), using: fetcher)
        #expect(permissions(folder.path("LICENSE")) == 0o600)
        fetcher.set(license.url, Data("changed".utf8))
        await #expect(throws: JerdError.self) { try await license.fetch(to: folder.path("OTHER"), using: fetcher) }
        #expect(FileProbe.presence(at: folder.path("OTHER")) == .absent)
    }
}

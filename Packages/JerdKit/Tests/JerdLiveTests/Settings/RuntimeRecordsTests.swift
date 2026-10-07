import Foundation
import JerdDatabases
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdStorage
import JerdTunnels
import JerdUI
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Runtime records")
struct RuntimeRecordsTests {
    static let phpBuild = SettingsSamples.build(
        .php, version: "8.4.1", executable: "bin/php", secondary: "sbin/php-fpm")
    static let mysqlBuild = SettingsSamples.build(.mysql, version: "8.4.6")
    static let mailBuild = SettingsSamples.build(.mailpit, version: "1.31.3")
    static let storageBuild = SettingsSamples.build(.rustfs, version: "1.0.0")
    static let tunnelBuild = SettingsSamples.build(.cloudflared, version: "2025.1.0")
    static let composerBuild = SettingsSamples.build(.composer, version: "2.10.3", executable: "composer.phar")

    static func records(defaultID: UUID = UUID()) -> RuntimeRecords {
        RuntimeRecords(
            sites: AppConfiguration(
                runtimes: [
                    SettingsSamples.php(phpBuild.executable.path, version: "8.4.1", id: defaultID),
                    SettingsSamples.php("/opt/homebrew/bin/php", version: "8.3.9"),
                ], defaultRuntimeID: defaultID, caddy: SettingsSamples.caddy()),
            databases: [
                try! RuntimeActivator.databaseRuntime(mysqlBuild),
                DatabaseRuntime(id: "redis-8", engine: .redis, version: "8.8.3", path: "/nonexistent/redis"),
            ],
            mail: RuntimeActivator.mailRuntime(mailBuild), storage: RuntimeActivator.storageRuntime(storageBuild),
            tunnel: TunnelRuntime(version: "2025.1.0", directory: tunnelBuild.directory),
            companions: CLICompanions(
                composerPath: composerBuild.executable.path, laravelPath: "/nonexistent/laravel",
                composerVersion: "2.10.3", laravelVersion: "5.32.0"))
    }

    @Test func versionsListTheRecordOfEveryOwner() {
        let versions = Self.records().versions

        #expect(versions[.php] == ["8.4.1", "8.3.9"])
        #expect(versions[.caddy] == ["2.11.4"])
        #expect(versions[.composer] == ["2.10.3"])
        #expect(versions[.laravel] == ["5.32.0"])
        #expect(versions[.mysql] == ["8.4.6"])
        #expect(versions[.postgresql] == [])
        #expect(versions[.redis] == ["8.8.3"])
        #expect(versions[.mailpit] == ["1.31.3"])
        #expect(versions[.rustfs] == ["1.0.0"])
        #expect(versions[.cloudflared] == ["2025.1.0"])
    }

    @Test func emptyRecordsHaveNoVersions() {
        let versions = RuntimeRecords().versions.values.flatMap { $0 }
        #expect(versions.isEmpty)
    }

    @Test(arguments: [("v2.11.4 h1:abc=", "2.11.4"), ("v2.10.0", "2.10.0"), ("2.9.1", "2.9.1")])
    func caddyVersionDropsThePrefixAndTheBuildInfo(reported: String, version: String) {
        #expect(RuntimeRecords.caddyVersion(reported) == version)
    }

    @Test func aBuildIsInUseWhenItsOwnerRecordPointsAtIt() {
        let records = Self.records()
        for build in [Self.phpBuild, Self.mysqlBuild, Self.mailBuild, Self.storageBuild, Self.tunnelBuild] {
            #expect(records.isInUse(build), "\(build.kind)")
        }
        #expect(records.isInUse(Self.composerBuild))
    }

    @Test func aBuildThatNoRecordNamesIsNotInUse() {
        let records = Self.records()
        #expect(!records.isInUse(SettingsSamples.build(.php, version: "8.5.0", executable: "bin/php")))
        #expect(!records.isInUse(SettingsSamples.build(.caddy)))
        #expect(!records.isInUse(SettingsSamples.build(.laravel, executable: "bin/laravel")))
        #expect(!records.isInUse(SettingsSamples.build(.postgresql)))
        #expect(!RuntimeRecords().isInUse(Self.mailBuild))
    }

    @Test func theSnapshotListsOnlyBuildsInUseAndThePHPDigests() {
        let defaultID = UUID()
        let unused = SettingsSamples.build(.mailpit, version: "1.30.0", digest: "old")
        let snapshot = Self.records(defaultID: defaultID).snapshot(managed: [Self.phpBuild, Self.mysqlBuild, unused])

        #expect(snapshot.builds.map(\.kind) == [.php, .mysql])
        #expect(snapshot.builds.first == RuntimeRecords.installedBuild(Self.phpBuild))
        #expect(snapshot.phpBuildDigests == [defaultID: "abc"])
        #expect(snapshot.versions[.php] == ["8.4.1", "8.3.9"])
    }

    @Test func anInstalledBuildKeepsKindVersionsAndDigest() {
        let build = SettingsSamples.build(.postgresql, version: "18.6", digest: "d1")
        #expect(
            RuntimeRecords.installedBuild(build)
                == InstalledBuild(kind: .postgresql, version: "18.6", releaseVersion: "18.6", archiveSHA256: "d1"))
    }

    @Test func preparationToolsUseTheDefaultPHPAndTheSelectedComposer() {
        let tools = Self.records().preparationTools(lzma: nil)

        #expect(tools.phpCLI == Self.phpBuild.executable)
        #expect(tools.composer == Self.composerBuild.executable)
        #expect(tools.lzma == nil)
        #expect(RuntimeRecords().preparationTools(lzma: nil).phpCLI == nil)
    }
}

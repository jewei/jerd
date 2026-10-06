import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdStorage
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Runtime activation")
struct RuntimeActivatorTests {
    let owners = RecordingRuntimeOwners()
    let inspector = FakeExecutableInspector()

    func activator(_ sites: RecordingSiteChanges) -> RuntimeActivator {
        RuntimeActivator(owners: owners, sites: sites, inspector: inspector)
    }

    static let php = SettingsSamples.build(.php, version: "8.5.0", executable: "bin/php", secondary: "sbin/php-fpm")

    @Test func phpAsDefaultIsRegisteredThenMadeTheDefaultThroughTheSiteTransaction() async throws {
        let existing = SettingsSamples.php("/opt/homebrew/bin/php")
        let sites = RecordingSiteChanges(AppConfiguration(runtimes: [existing], defaultRuntimeID: existing.id))

        try await activator(sites).activate(Self.php, useAsDefault: true)

        let saved = await sites.configuration
        let added = try #require(saved.runtimes.first { $0.cliPath == Self.php.executable.path })
        #expect(saved.defaultRuntimeID == added.id)
        let changes = await sites.changes
        #expect(changes.count == 2)
        #expect(changes.last == .defaultRuntime(added.id))
        #expect(await inspector.inspected == [Self.php.executable])
    }

    @Test func phpInstallOnlyKeepsTheDefault() async throws {
        let existing = SettingsSamples.php("/opt/homebrew/bin/php")
        let sites = RecordingSiteChanges(AppConfiguration(runtimes: [existing], defaultRuntimeID: existing.id))

        try await activator(sites).activate(Self.php, useAsDefault: false)

        #expect(await sites.configuration.defaultRuntimeID == existing.id)
        #expect(await sites.changes.count == 1)
    }

    @Test func phpWithoutFPMIsRefusedBeforeAnyChange() async {
        let sites = RecordingSiteChanges()
        let build = SettingsSamples.build(.php, executable: "bin/php")

        await #expect(throws: JerdError.invalid("The PHP-FPM executable is missing.")) {
            try await activator(sites).activate(build, useAsDefault: true)
        }
        #expect(await sites.changes.isEmpty)
    }

    @Test func caddyIsInspectedAndSelectedThroughTheSiteTransaction() async throws {
        let sites = RecordingSiteChanges()
        let build = SettingsSamples.build(.caddy, version: "2.11.4")

        try await activator(sites).activate(build, useAsDefault: true)

        #expect(await sites.configuration.caddy?.path == build.executable.path)
    }

    @Test func databaseMailAndStorageBuildsGoToTheirManagers() async throws {
        let sites = RecordingSiteChanges()
        let redis = SettingsSamples.build(.redis, version: "8.8.3")
        let mail = SettingsSamples.build(.mailpit, version: "1.31.3")
        let storage = SettingsSamples.build(.rustfs, version: "1.0.0")

        for build in [redis, mail, storage] {
            try await activator(sites).activate(build, useAsDefault: true)
        }

        #expect(
            await owners.calls == [
                .database(
                    DatabaseRuntime(id: redis.folderName, engine: .redis, version: "8.8.3", path: redis.directory.path)),
                .mail(MailRuntime(id: mail.folderName, version: "1.31.3", path: mail.directory.path)),
                .storage(StorageRuntime(id: storage.folderName, version: "1.0.0", path: storage.directory.path)),
            ])
        #expect(await sites.changes.isEmpty)
    }

    @Test func cloudflaredIsUsedByItsInstalledExecutable() async throws {
        let build = SettingsSamples.build(.cloudflared, version: "2025.1.0", executable: "cloudflared")

        try await activator(RecordingSiteChanges()).activate(build, useAsDefault: true)

        #expect(await owners.calls == [.tunnel(build.directory.appendingPathComponent("cloudflared"))])
    }

    @Test(arguments: [RuntimeKind.composer, .laravel])
    func composerAndLaravelAreSelectedInTheCLIToolsRecord(kind: RuntimeKind) async throws {
        let build = SettingsSamples.build(kind)

        try await activator(RecordingSiteChanges()).activate(build, useAsDefault: true)

        #expect(await owners.calls == [.companion(build.id)])
    }

    @Test func aDatabaseRecordOfAnotherKindIsRefused() {
        #expect(throws: JerdError.self) { try RuntimeActivator.databaseRuntime(SettingsSamples.build(.mailpit)) }
    }

    @Test func aCommittedChangeReturnsTheSavedConfiguration() throws {
        let saved = AppConfiguration(caddy: SettingsSamples.caddy())
        #expect(try SiteChangeCommit.require(.committed(saved)) == saved)
    }

    @Test func aChangeThatWaitsForApprovalIsReportedAndNotResumed() {
        let setup = HTTPSSetup(
            registration: HTTPSRegistration(
                installationID: UUID(), hostnames: ["a.test"], certificateDER: Data(), trustPolicy: .serverTLS))
        let step = SiteChangeStep.needsApproval(setup) {
            Issue.record("A Settings change must not resume an approval.")
            return AppConfiguration()
        }

        #expect(throws: JerdError.unavailable(SiteChangeCommit.approvalMessage)) {
            try SiteChangeCommit.require(step)
        }
    }
}

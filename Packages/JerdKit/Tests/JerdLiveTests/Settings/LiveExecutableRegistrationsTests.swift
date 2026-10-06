import Foundation
import JerdFoundation
import JerdUI
import JerdWeb
import Testing

@testable import JerdLive

/// A configuration source with a fixed configuration and setup message.
actor FakeSiteConfiguration: SiteConfigurationReading {
    let configuration: AppConfiguration
    let message: String?
    private(set) var loads = 0

    init(_ configuration: AppConfiguration, message: String?) {
        self.configuration = configuration
        self.message = message
    }

    func loadConfiguration() -> AppConfiguration {
        loads += 1
        return configuration
    }
}

@Suite("Live executable registrations")
struct LiveExecutableRegistrationsTests {
    static let php = SettingsSamples.php("/opt/homebrew/bin/php", version: "8.3.9")

    func port(
        _ sites: RecordingSiteChanges, inspector: FakeExecutableInspector = .init()
    ) -> LiveExecutableRegistrations {
        LiveExecutableRegistrations(
            configuration: FakeSiteConfiguration(AppConfiguration(), message: nil), sites: sites, inspector: inspector)
    }

    @Test func registrationsReadTheLoadedConfigurationAndTheSetupMessage() async throws {
        let configuration = AppConfiguration(
            runtimes: [Self.php], defaultRuntimeID: Self.php.id, caddy: SettingsSamples.caddy())
        let source = FakeSiteConfiguration(configuration, message: DevelopmentRuntimeSetup.readyMessage)
        let port = LiveExecutableRegistrations(
            configuration: source, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector())

        let registrations = try await port.registrations()

        #expect(
            registrations
                == LocalRuntimeRegistrations(
                    php: [Self.php], defaultPHPID: Self.php.id, caddyVersion: "v2.11.4 h1:x=",
                    setupMessage: DevelopmentRuntimeSetup.readyMessage))
        #expect(await source.loads == 1)
    }

    @Test func importPHPInspectsThenRegistersThroughTheSiteTransaction() async throws {
        let sites = RecordingSiteChanges()
        let inspector = FakeExecutableInspector()
        let cli = URL(fileURLWithPath: "/opt/php/bin/php")

        try await port(sites, inspector: inspector).importPHP(
            cli: cli, fpm: URL(fileURLWithPath: "/opt/php/sbin/php-fpm"))

        #expect(await inspector.inspected == [cli])
        #expect(await sites.configuration.runtimes.map(\.cliPath) == [cli.path])
    }

    @Test func importCaddySelectsTheInspectedCaddy() async throws {
        let sites = RecordingSiteChanges()
        let caddy = URL(fileURLWithPath: "/opt/caddy/caddy")

        try await port(sites).importCaddy(caddy)

        #expect(await sites.configuration.caddy?.path == caddy.path)
    }

    @Test func removeAndDefaultAreSiteChanges() async throws {
        let other = SettingsSamples.php("/opt/other/php")
        let sites = RecordingSiteChanges(AppConfiguration(runtimes: [Self.php, other], defaultRuntimeID: Self.php.id))
        let port = port(sites)

        try await port.setDefaultPHP(other.id)
        try await port.removePHP(Self.php.id)

        #expect(await sites.changes == [.defaultRuntime(other.id), .removeRuntime(Self.php.id)])
        #expect(await sites.configuration.runtimes == [other])
    }

    @Test func removingTheDefaultPHPIsRefusedByTheTransaction() async {
        let sites = RecordingSiteChanges(AppConfiguration(runtimes: [Self.php], defaultRuntimeID: Self.php.id))

        await #expect(throws: JerdError.self) { try await port(sites).removePHP(Self.php.id) }
        #expect(await sites.configuration.runtimes == [Self.php])
    }
}

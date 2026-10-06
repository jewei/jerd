import Foundation
import JerdFoundation
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Bundled PHP and Caddy setup")
struct DevelopmentRuntimeSetupTests {
    @Test func aFirstLaunchInstallsAndRegistersPHPAndCaddyThroughTheTransaction() async throws {
        let registry = FakeSiteRegistry()
        let sites = RecordingSiteTransaction(registry: registry)
        let source = FakeDevelopmentSource()
        let setup = DevelopmentRuntimeSetup(registry: registry, sites: sites, source: source)

        let configuration = try await setup.loadConfiguration()

        #expect(await sites.changes == [.upsertRuntime(source.records.php), .caddy(source.records.caddy)])
        #expect(configuration.defaultRuntimeID == source.records.php.id)
        #expect(configuration.caddy == source.records.caddy)
        #expect(await setup.message == DevelopmentRuntimeSetup.readyMessage)
    }

    @Test func theUsersOwnCaddyStays() async throws {
        let own = SampleWeb.caddy(path: "/opt/caddy")
        let registry = FakeSiteRegistry(SampleWeb.configuration(caddy: own))
        let sites = RecordingSiteTransaction(registry: registry)
        let source = FakeDevelopmentSource()

        _ = try await DevelopmentRuntimeSetup(registry: registry, sites: sites, source: source).loadConfiguration()

        #expect(await sites.changes == [.upsertRuntime(source.records.php)])
    }

    @Test func nothingInstallsWhenTheRuntimesAreInPlace() async throws {
        let registry = FakeSiteRegistry(SampleWeb.configuration(php: SampleWeb.php(), caddy: SampleWeb.caddy()))
        let sites = RecordingSiteTransaction(registry: registry)
        let source = FakeDevelopmentSource(needed: false)
        let setup = DevelopmentRuntimeSetup(registry: registry, sites: sites, source: source)

        _ = try await setup.loadConfiguration()

        #expect(await source.installCount == 0)
        #expect(await sites.changes.isEmpty)
        #expect(await setup.message == DevelopmentRuntimeSetup.readyMessage)
    }

    @Test func aFailedBundledSetupKeepsTheSitesUsableAndSaysWhy() async throws {
        let registry = FakeSiteRegistry(SampleWeb.configuration(sites: [SampleWeb.site()]))
        let source = FakeDevelopmentSource(failure: .invalid("The runtime payload is incomplete."))
        let setup = DevelopmentRuntimeSetup(registry: registry, sites: RecordingSiteTransaction(), source: source)

        let configuration = try await setup.loadConfiguration()

        #expect(configuration.sites == [SampleWeb.site()])
        #expect(await setup.message == "Bundled runtime setup failed: The runtime payload is incomplete.")
    }

    @Test func aCorruptFileFailsTheLoadInstallsNothingAndCanBeRetried() async throws {
        let registry = FakeSiteRegistry(loadFailures: 1)
        let source = FakeDevelopmentSource()
        let setup = DevelopmentRuntimeSetup(
            registry: registry, sites: RecordingSiteTransaction(registry: registry), source: source)

        await #expect(throws: JerdError.self) { try await setup.loadConfiguration() }
        #expect(await source.installCount == 0)
        #expect(await setup.message == nil)

        _ = try await setup.loadConfiguration()
        #expect(await source.installCount == 1)
    }

    @Test func concurrentLoadsRunTheSetupOnce() async throws {
        let registry = FakeSiteRegistry()
        let source = FakeDevelopmentSource()
        let setup = DevelopmentRuntimeSetup(
            registry: registry, sites: RecordingSiteTransaction(registry: registry), source: source)

        async let first = setup.loadConfiguration()
        async let second = setup.loadConfiguration()
        _ = try await (first, second)
        _ = try await setup.loadConfiguration()

        #expect(await source.installCount == 1)
        #expect(await registry.loadCount == 1)
    }

    @Test func recordChangesAddPHPAlwaysAndCaddyOnlyWhenNoneIsSelected() {
        let records = DevelopmentRuntimeRecords(php: SampleWeb.php(), caddy: SampleWeb.caddy())

        #expect(records.changes(for: AppConfiguration()) == [.upsertRuntime(records.php), .caddy(records.caddy)])
        #expect(
            records.changes(for: SampleWeb.configuration(caddy: SampleWeb.caddy(path: "/own/caddy")))
                == [.upsertRuntime(records.php)])
    }
}

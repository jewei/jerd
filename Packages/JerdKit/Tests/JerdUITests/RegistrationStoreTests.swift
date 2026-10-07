import Foundation
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdSnapshotSupport
@testable import JerdUI

@Suite("One registration store for Runtimes, Advanced, and the dashboard", .serialized)
@MainActor
struct RegistrationStoreTests {
    private let php83 = RegisteredPHP(id: SampleData.php83ID, version: "8.3.24")

    @Test("Use as Default on Runtimes shows at once on Advanced and in the dashboard row")
    func defaultChangeShowsEverywhere() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        await fixture.state.runtimes.useAsDefault(php83)?.value
        #expect(fixture.state.runtimes.defaultPHPID == SampleData.php83ID)
        #expect(fixture.state.advanced.registrations.defaultPHPID == SampleData.php83ID)
        #expect(fixture.state.registrations.defaultPHP?.version == "8.3.24")
    }

    @Test("Remove Registration on Advanced removes the PHP from Runtimes at once")
    func removalShowsOnRuntimes() async throws {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        let runtime = try #require(fixture.state.advanced.registrations.php.last)
        fixture.state.advanced.confirmation = .removePHP(runtime)
        await fixture.state.advanced.confirm()?.value
        #expect(fixture.state.runtimes.registeredPHP.map(\.id) == [SampleData.php84ID])
    }

    @Test("Install and Use reads the registrations again, so the new default shows everywhere")
    func installReloadsRegistrations() async throws {
        let ports = InMemoryAdvancedPorts(registrations: SampleData.registrations)
        let inventory = InMemoryRuntimeInventory(inventory: SampleData.inventory, results: SampleData.checks)
        let fixture = AppFixture(runtimes: inventory, advanced: ports)
        defer { fixture.removeDefaults() }
        let id = UUID()
        await inventory.configure { inventory in
            inventory.onActivate = { build, useAsDefault in
                await ports.register(Self.runtime(id: id, version: build.version), asDefault: useAsDefault)
            }
        }
        await fixture.state.launch()
        await fixture.state.runtimes.check()?.value
        await fixture.state.runtimes.install(try #require(fixture.state.runtimes.selectedRelease(.php)))?.value
        #expect(fixture.state.registrations.defaultPHP?.id == id)
        #expect(fixture.state.advanced.registrations.defaultPHPID == id)
    }

    @Test("Runtimes and Advanced read their data again each time they appear")
    func pagesReloadOnAppear() async throws {
        let ports = InMemoryAdvancedPorts(registrations: SampleData.registrations)
        let fixture = AppFixture(advanced: ports)
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        await ports.configure { $0.httpsStatus = SampleData.httpsRecovery }
        await ports.configure { $0.registrationsValue.defaultPHPID = SampleData.php83ID }
        fixture.state.navigation.show(.dashboard(.advanced))
        _ = try await SnapshotRenderer().render(
            JerdWorkspace(state: fixture.state), size: .compact, appearance: .light, chrome: .window(title: "Jerd"),
            isReady: { fixture.state.advanced.httpsRecovery != nil })
        #expect(fixture.state.advanced.httpsRecovery == SampleData.httpsRecovery)
        #expect(fixture.state.registrations.defaultPHP?.id == SampleData.php83ID)
    }

    nonisolated static func runtime(id: UUID, version: String) -> DevelopmentRuntime {
        DevelopmentRuntime(
            id: id, cliPath: "/opt/php-\(version)/bin/php", fpmPath: "/opt/php-\(version)/sbin/php-fpm",
            version: version, architectures: [.arm64], cliExtensions: [], fpmExtensions: [], inspectedAt: SampleData.now
        )
    }
}

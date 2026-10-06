import Foundation
import JerdServiceKit
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

/// On the first launch Jerd installs the bundled runtimes inside
/// each feature's load. Until the load ends, a card says that Jerd prepares the runtime, and it
/// never tells the user to install what Jerd is installing. A disabled action says why.
@Suite("Cards while Jerd prepares the runtimes")
@MainActor
struct CardPreparingTests {
    private static func fixture(
        mail: InMemoryMail = InMemoryMail(), storage: InMemoryStorage = InMemoryStorage(),
        databases: InMemoryDatabases = InMemoryDatabases()
    ) -> AppFixture {
        AppFixture(services: InMemoryServicePorts(databases: databases, storage: storage, mail: mail))
    }

    // MARK: The notice

    @Test("The notice says Preparing while the load runs, and Not installed only after it ended")
    func noticePerLoadState() {
        let preparing = ServiceCardNotice.notice(
            load: .loading, hasRuntime: false, runtime: "Mailpit", settings: "Mail")
        #expect(preparing?.text == "Preparing Mailpit…")
        #expect(preparing?.reason == "Jerd is preparing Mailpit.")
        #expect(preparing?.isPreparing == true)

        let missing = ServiceCardNotice.notice(load: .loaded, hasRuntime: false, runtime: "Mailpit", settings: "Mail")
        #expect(missing?.text == "Mailpit is not installed. Install it in Runtimes.")
        #expect(missing?.reason == "Install Mailpit in Runtimes first.")
        #expect(missing?.isPreparing == false)

        let failed = ServiceCardNotice.notice(
            load: .failed(message: "mail.json"), hasRuntime: false, runtime: "Mailpit", settings: "Mail")
        #expect(failed?.text == "Mail settings could not be loaded.")
        #expect(ServiceCardNotice.notice(load: .loaded, hasRuntime: true, runtime: "Mailpit", settings: "Mail") == nil)
    }

    // MARK: Each card while preparing

    @Test("Mail: Preparing, with Start off and the reason, before the load ends")
    func mailWhilePreparing() {
        let fixture = Self.fixture()
        defer { fixture.removeDefaults() }
        let summary = fixture.state.mail.summary
        #expect(summary.status.label == "Preparing…")
        #expect(summary.status.tone == .busy)
        #expect(summary.summary == "Preparing Mailpit…")
        #expect(summary.actions.map(\.title) == ["Start"])
        #expect(summary.actions.first?.isEnabled == false)
        #expect(summary.actions.first?.unavailableReason == "Jerd is preparing Mailpit.")
    }

    @Test("Storage: Preparing, with Start off and the reason, before the load ends")
    func storageWhilePreparing() {
        let fixture = Self.fixture()
        defer { fixture.removeDefaults() }
        let summary = fixture.state.storage.summary
        #expect(summary.status.label == "Preparing…")
        #expect(summary.summary == "Preparing RustFS…")
        #expect(summary.actions.first?.isEnabled == false)
        #expect(summary.actions.first?.unavailableReason == "Jerd is preparing RustFS.")
    }

    @Test("Databases: Preparing, and Add Database… off with the reason, before the load ends")
    func databasesWhilePreparing() {
        let fixture = Self.fixture()
        defer { fixture.removeDefaults() }
        let summary = fixture.state.databases.summary
        #expect(summary.status.label == "Preparing…")
        #expect(summary.summary == "Preparing database runtimes…")
        #expect(summary.actions.map(\.title) == ["Add Database…"])
        #expect(summary.actions.first?.isEnabled == false)
        #expect(summary.actions.first?.unavailableReason == "Jerd is preparing database runtimes.")
    }

    @Test("Sites: while the first load runs, the empty card offers Add Site… with the reason, never Stop All")
    func sitesWhilePreparing() async {
        let port = InMemorySitesPort(configuration: AppConfiguration())
        await port.configure { $0.holdsLoad = true }
        let harness = SitesHarness(sites: port)
        let launch = Task { await harness.model.launch() }
        while !harness.model.operation.isWorking { await Task.yield() }

        let summary = harness.model.summary
        #expect(summary.status.label == "Preparing…")
        #expect(summary.summary == "Preparing your sites…")
        #expect(summary.actions.map(\.title) == ["Add Site…"])
        #expect(summary.actions.first?.isEnabled == false)
        #expect(summary.actions.first?.unavailableReason == "Jerd is preparing your sites.")

        await port.releaseLoad()
        await launch.value
        #expect(harness.model.summary.status.label == "No sites")
        #expect(harness.model.summary.actions.first?.isEnabled == true)
    }

    // MARK: After the load

    @Test("Mail and Storage say Not installed only after a load without a runtime")
    func notInstalledAfterTheLoad() async {
        let fixture = Self.fixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        #expect(fixture.state.mail.summary.summary == "Mailpit is not installed. Install it in Runtimes.")
        #expect(fixture.state.mail.summary.status.label == "Stopped")
        #expect(fixture.state.mail.summary.actions.first?.unavailableReason == "Install Mailpit in Runtimes first.")
        #expect(fixture.state.storage.summary.summary == "RustFS is not installed. Install it in Runtimes.")
    }

    @Test("Databases without an installed engine say so, and Add Database… says why it is off")
    func databasesWithoutRuntime() async {
        let fixture = Self.fixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        let summary = fixture.state.databases.summary
        #expect(summary.summary == "No database runtime is installed. Install one in Runtimes.")
        #expect(summary.actions.first?.unavailableReason == "Install MySQL, PostgreSQL, or Redis in Runtimes first.")
    }

    @Test("An action that is on has no reason, so its tooltip stays the full title")
    func enabledActionHasNoReason() {
        let action = FeatureAction(id: "a", title: "Stop", spokenTitle: "Stop Mail", unavailableReason: "x") {}
        #expect(action.unavailableReason == nil)
        #expect(FeatureCard.help(for: action) == "Stop Mail")
        let off = FeatureAction(id: "b", title: "Start", isEnabled: false, unavailableReason: "Why") {}
        #expect(FeatureCard.help(for: off) == "Why")
        #expect(off.titled("Go").unavailableReason == "Why")
    }
}

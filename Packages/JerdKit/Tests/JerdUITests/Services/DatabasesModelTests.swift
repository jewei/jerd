import Foundation
import JerdDatabases
import JerdDesign
import JerdServiceKit
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Databases model")
@MainActor
struct DatabasesModelTests {
    private func launched(_ databases: InMemoryDatabases) async -> AppFixture {
        let fixture = AppFixture(
            services: InMemoryServicePorts(databases: databases, storage: InMemoryStorage(), mail: InMemoryMail()))
        await fixture.state.launch()
        return fixture
    }

    private func sample() -> InMemoryDatabases {
        InMemoryDatabases(
            configuration: SampleServices.databases(.populated), states: SampleServices.databaseStates(.populated),
            started: [SampleServices.studioID, SampleServices.cacheID], retained: SampleServices.retained)
    }

    @Test("Add registers the service, starts it, selects it, and closes the sheet")
    func addCreatesAndStarts() async throws {
        let databases = InMemoryDatabases(configuration: SampleServices.databases(.empty))
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.postgresql)
        #expect(model.sheet == .editor)
        // The fixture suggests the engine default plus one: 5433 for PostgreSQL.
        await waitUntil { model.editor?.portText == "5433" }
        await model.saveEditor()?.value
        await waitUntil {
            model.busyServices.isEmpty && model.services.first.map { model.state(of: $0.id).isRunning } == true
        }
        let service = try #require(model.services.first)
        #expect(service.name == "PostgreSQL")
        #expect(model.sheet == nil)
        #expect(fixture.state.navigation.selection(in: .databases) == .database(service.id))
    }

    @Test("A registry failure stays in the editor sheet")
    func addFailureStaysInSheet() async {
        let databases = InMemoryDatabases(configuration: SampleServices.databases(.empty))
        await databases.configure { $0.failure = "Port 3307 is in use by another program." }
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        model.editor?.setPort("3307")
        await model.saveEditor()?.value
        #expect(model.editorOperation == .failed(message: "Port 3307 is in use by another program."))
        #expect(model.sheet == .editor)
        #expect(model.operation == .idle)
    }

    @Test("Edit needs a stopped service and saves the new name and port")
    func edit() async {
        let fixture = await launched(sample())
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginEdit(SampleServices.studioID)
        #expect(model.editor == nil)
        model.beginEdit(SampleServices.reportingID)
        model.editor?.setName("Reports")
        model.editor?.setPort("5440")
        await model.saveEditor()?.value
        #expect(model.service(SampleServices.reportingID)?.name == "Reports")
        #expect(model.service(SampleServices.reportingID)?.port == 5440)
    }

    @Test("Remove asks first, keeps the data, and lists it for Restore")
    func removeThenRestore() async throws {
        let fixture = await launched(sample())
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(model.confirmRemove() == nil)
        model.requestRemove(SampleServices.studioID)
        #expect(model.pendingRemoval?.id == SampleServices.studioID)
        await model.confirmRemove()?.value
        #expect(model.service(SampleServices.studioID) == nil)
        model.showRetained()
        await waitUntil { !model.retainedOperation.isWorking }
        let retained = try #require(model.retained.first { $0.id == SampleServices.studioID })
        model.beginRestore(retained)
        #expect(model.sheet == .restore)
        await model.saveRestore()?.value
        #expect(model.service(SampleServices.studioID)?.name == "Studio development")
        #expect(model.sheet == nil)
        #expect(fixture.state.navigation.selection(in: .databases) == .database(SampleServices.studioID))
    }

    @Test("A folder with a problem cannot be restored")
    func restoreRefusesProblem() async {
        let fixture = await launched(sample())
        defer { fixture.removeDefaults() }
        fixture.state.databases.beginRestore(SampleServices.retained[1])
        #expect(fixture.state.databases.restoreDraft == nil)
    }

    @Test("A start in progress shows Starting… until the service reports its own state")
    func startingStatus() async throws {
        let databases = sample()
        await databases.configure { $0.startBehavior = .suspend }
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(model.displayStatus(of: SampleServices.reportingID) == DisplayStatus("Stopped", tone: .idle))
        let start = try #require(model.start(SampleServices.reportingID))
        #expect(model.displayStatus(of: SampleServices.reportingID) == DisplayStatus("Starting…", tone: .busy))
        start.cancel()
        await start.value
    }

    @Test("Services start and stop on their own; a start failure shows only as its state")
    func independentLifecycle() async {
        let databases = sample()
        await databases.configure { $0.startBehavior = .fail("PostgreSQL exited.") }
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        let start = model.start(SampleServices.reportingID)
        #expect(model.busyServices == [SampleServices.reportingID])
        #expect(model.canStop(SampleServices.studioID))
        await start?.value
        #expect(model.state(of: SampleServices.reportingID) == .failed(reason: "PostgreSQL exited."))
        #expect(model.operation == .idle)
        #expect(model.status == DisplayStatus("Failed", tone: .failed))
    }

    @Test("Copy Password needs a service that started once")
    func copyPassword() async {
        let fixture = await launched(sample())
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        fixture.state.navigation.show(.item(.database(SampleServices.studioID)))
        await model.copyPassword(SampleServices.studioID).value
        #expect(fixture.shell.pasteboard == ["sample-password-3306"])
        fixture.state.navigation.show(.item(.database(SampleServices.reportingID)))
        await model.copyEnvironment(SampleServices.reportingID).value
        #expect(model.operation.failureMessage == "Start the service once to create its credentials.")
    }

    @Test("The card status puts problems first, then work, then the running count")
    func cardStatus() async {
        let databases = sample()
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(model.status == DisplayStatus("2 of 3 running", tone: .ready))
        await databases.configure { $0.states[SampleServices.cacheID] = .stuck(pid: 9, reason: "x") }
        await model.refresh()
        #expect(model.status == DisplayStatus("Did not stop", tone: .attention))
        #expect(model.summary.summary == "Studio development, Studio cache, Reporting")
    }

    @Test("The empty card offers Add Database… as the next step")
    func emptyCard() async throws {
        let fixture = await launched(InMemoryDatabases(configuration: SampleServices.databases(.empty)))
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(model.status == DisplayStatus("No services", tone: .idle))
        let add = try #require(model.summary.actions.first)
        #expect(add.isPrimary)
        add.perform()
        #expect(fixture.state.navigation.section == .databases)
        #expect(model.editor?.engine == .mysql)
    }

    @Test("The card has Start All while a service is stopped; it starts only the stopped ones")
    func cardActions() async throws {
        let databases = sample()
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        let actions = model.summary.actions
        #expect(actions.map(\.title) == ["Start All"])
        #expect(actions.map(\.isPrimary) == [true])
        try #require(actions.first).perform()
        await waitUntil { model.busyServices.isEmpty && model.state(of: SampleServices.reportingID).isRunning }
        #expect(await databases.calls.filter { $0.hasPrefix("start") }.count == 1)
        #expect(model.summary.actions.map(\.title) == ["Stop All"])
        #expect(model.summary.actions.map(\.isPrimary) == [false])
    }

    @Test("The menu has Start or Stop for each service")
    func menu() async {
        let fixture = await launched(sample())
        defer { fixture.removeDefaults() }
        guard case .submenu(_, let items) = fixture.state.databases.menuItems.first?.kind else {
            Issue.record("Expected a submenu")
            return
        }
        #expect(items.map(\.title) == ["Stop Studio development", "Stop Studio cache", "Start Reporting"])
    }

    @Test("Quit stops every service; a failure keeps Jerd open with the reason on the page")
    func shutdown() async {
        let databases = sample()
        await databases.configure { $0.stopBehavior = .fail("MySQL did not stop.") }
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(await model.shutdown() == false)
        #expect(model.operation.failureMessage == "MySQL did not stop.")
        #expect(model.start(SampleServices.reportingID) == nil)
        model.resumeAfterCancelledQuit()
        await databases.configure { $0.stopBehavior = .succeed }
        #expect(await model.shutdown())
        #expect(await databases.calls.filter { $0 == "stop all" }.count == 2)
    }

    @Test("A cancelled Quit shows a stuck stop once, as the service state, not also as a banner")
    func cancelledQuitShowsTheStuckStopOnce() async {
        let databases = sample()
        await databases.configure { $0.stopBehavior = .stuck("MySQL did not stop safely.") }
        let fixture = await launched(databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(await model.shutdown() == false)
        #expect(model.services.contains { model.state(of: $0.id).failure == "MySQL did not stop safely." })
        #expect(model.operation.failureMessage == nil)
    }

    @Test("Quit waits for a running start before it stops the services")
    func shutdownWaitsForWork() async {
        let fixture = await launched(sample())
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.start(SampleServices.reportingID)
        #expect(await model.shutdown())
        #expect(model.busyServices.isEmpty)
        #expect(model.state(of: SampleServices.reportingID) == .stopped)
    }
}

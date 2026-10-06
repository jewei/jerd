import Foundation
import JerdDesign
import JerdServiceKit
import JerdUIFixtures
import Testing

@testable import JerdUI

/// The section toolbars of Databases and Storage, the Return key of Retained Databases, and the
/// page controls that start work while a quit runs but the service's own stage has not started.
@Suite("Service toolbars and controls during a quit")
@MainActor
struct ServiceToolbarAndQuitTests {
    private func launched() async -> AppFixture {
        let fixture = AppFixture()
        await fixture.state.launch()
        return fixture
    }

    private func titles(_ actions: [PageAction]) -> [String] { actions.map(\.title) }
    private func enabled(_ actions: [PageAction]) -> [Bool] { actions.map(\.isEnabled) }

    @Test("The Databases toolbar opens Retained Databases and shows the runtimes")
    func databasesToolbar() async throws {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        let actions = DatabasesToolbar.actions(for: model, isQuitting: false)
        #expect(titles(actions) == ["Retained Databases…", "Database Runtimes"])
        #expect(actions.map(\.identifier) == ["databases.toolbar.retained", "databases.toolbar.runtimes"])
        #expect(actions.map(\.systemImage) == ["arrow.uturn.backward.circle", "shippingbox"])
        #expect(enabled(actions) == [true, true])
        actions[0].perform()
        #expect(model.sheet == .retained)
        model.closeRetained()
        actions[1].perform()
        #expect(fixture.state.navigation.section == .dashboard)
        #expect(enabled(DatabasesToolbar.actions(for: model, isQuitting: true)) == [false, true])
    }

    @Test("The Storage toolbar refreshes the buckets while running and edits the ports while stopped")
    func storageToolbar() async throws {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        var actions = StorageToolbar.actions(for: model, isQuitting: false)
        #expect(titles(actions) == ["Refresh Buckets", "Storage Settings"])
        #expect(actions.map(\.identifier) == ["storage.toolbar.refresh", "storage.toolbar.settings"])
        #expect(enabled(actions) == [true, false])
        #expect(actions[1].help == "Stop storage to change its ports.")
        actions[0].perform()
        #expect(model.operation == .working("Listing buckets…"))
        await waitUntil { !model.operation.isWorking }
        #expect(await fixture.services.storage.calls.contains("refresh buckets"))
        #expect(enabled(StorageToolbar.actions(for: model, isQuitting: true)) == [false, false])

        await model.stop()?.value
        actions = StorageToolbar.actions(for: model, isQuitting: false)
        #expect(enabled(actions) == [false, true])
        #expect(actions[0].help == "Start storage to list its buckets.")
        actions[1].perform()
        #expect(model.portsDraft != nil)
    }

    @Test("During a quit, Start and Stop are off on every service page before the service's own stage")
    func headerControlsOffDuringQuit() async throws {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        let state = fixture.state
        await state.launch()
        let studio = try #require(state.databases.service(SampleServices.studioID))
        let reporting = try #require(state.databases.service(SampleServices.reportingID))
        #expect(
            DatabaseHeaderActions(model: state.databases, service: reporting, isQuitting: false).primary?.isEnabled
                == true)
        _ = state.requestTermination { _ in }
        // The databases and mail stages have not started, so only the quit turns their controls off.
        #expect(state.isQuitting)
        #expect(!state.databases.isShuttingDown)
        #expect(!state.mail.isShuttingDown)
        let quitting = state.isQuitting
        let start = DatabaseHeaderActions(model: state.databases, service: reporting, isQuitting: quitting).primary
        #expect(start?.title == "Start Service")
        #expect(start?.isEnabled == false)
        let stop = DatabaseHeaderActions(model: state.databases, service: studio, isQuitting: quitting).secondary
        #expect(enabled(stop) == [false])
        let mail = MailHeaderActions(model: state.mail, isQuitting: quitting)
        #expect(mail.primary?.title == "Open Inbox")
        #expect(mail.primary?.isEnabled == true, "Open Inbox starts no work")
        #expect(enabled(mail.secondary) == [false])
        let storage = StorageHeaderActions(model: state.storage, isQuitting: quitting)
        #expect(storage.secondary.allSatisfy { !$0.isEnabled })
    }

    @Test("Without a quit, the header controls follow the service state")
    func headerControlsWithoutQuit() async throws {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        let studio = try #require(state.databases.service(SampleServices.studioID))
        let running = DatabaseHeaderActions(model: state.databases, service: studio, isQuitting: false)
        #expect(running.primary == nil)
        #expect(titles(running.secondary) == ["Stop Service"])
        #expect(enabled(running.secondary) == [true])
        let mail = MailHeaderActions(model: state.mail, isQuitting: false)
        #expect(titles(mail.secondary) == ["Stop Mail"])
        #expect(enabled(mail.secondary) == [true])
        await state.mail.stop()?.value
        let stopped = MailHeaderActions(model: state.mail, isQuitting: false)
        #expect(stopped.primary?.title == "Start Mail")
        #expect(stopped.primary?.isEnabled == true)
        #expect(MailHeaderActions(model: state.mail, isQuitting: true).primary?.isEnabled == false)
    }

    @Test("Return closes Retained Databases with Done; Inspect Again is secondary and off during a quit")
    func retainedReturnKey() async {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        let confirmation = RetainedDatabasesSheet.confirmation(model: fixture.state.databases, isQuitting: false)
        #expect(confirmation.title == "Inspect Again")
        #expect(confirmation.cancelTitle == "Done")
        #expect(confirmation.returnKey == .cancel)
        #expect(confirmation.cancelUsesReturnKey)
        #expect(!confirmation.usesReturnKey)
        #expect(confirmation.isEnabled)
        #expect(!RetainedDatabasesSheet.confirmation(model: fixture.state.databases, isQuitting: true).isEnabled)
    }
}

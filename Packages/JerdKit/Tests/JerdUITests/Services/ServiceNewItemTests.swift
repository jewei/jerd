import Foundation
import JerdDatabases
import JerdDesign
import JerdServiceKit
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

/// How Databases, Storage, and Mail use File › New (⌘N) of the shell section API.
@Suite("File › New in the service sections")
@MainActor
struct ServiceNewItemTests {
    private func launched(_ services: InMemoryServicePorts = InMemoryServicePorts(.populated)) async -> AppFixture {
        let fixture = AppFixture(services: services)
        await fixture.state.launch()
        return fixture
    }

    /// A fixture whose quit waits in the storage stage, before the mail and database stages.
    private func quitting() async -> AppFixture {
        let fixture = AppFixture()
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        _ = fixture.state.requestTermination { _ in }
        return fixture
    }

    // MARK: File › New

    @Test("File › New Database… opens the Add sheet with the first engine, also with the sidebar hidden")
    func newDatabase() async throws {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        state.navigation.show(.section(.databases))
        state.navigation.toggleSidebar()
        let action = try #require(state.databases.newItemAction)
        #expect(action.id == "databases.new")
        #expect(AppCommand.newItem.title(in: state) == "New Database…")
        #expect(AppCommand.newItem.isEnabled(in: state))
        AppCommand.newItem.perform(in: state)
        #expect(state.databases.sheet == .editor)
        #expect(state.databases.editor?.engine == .mysql)
        #expect(state.databases.editor?.isAdding == true)
        #expect(!AppCommand.newItem.isEnabled(in: state), "A second ⌘N must not replace the open draft")
    }

    @Test("File › New Database… is off before the load, without runtimes, and during a registry change")
    func newDatabaseOff() async throws {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        #expect(fixture.state.databases.newItemAction?.isEnabled == false)

        let noRuntimes = InMemoryServicePorts(.populated)
        await noRuntimes.databases.configure { $0.configuration.runtimes = [] }
        let empty = await launched(noRuntimes)
        defer { empty.removeDefaults() }
        #expect(empty.state.databases.newItemAction?.isEnabled == false)

        let gate = FixtureGate()
        let gated = await launched()
        defer { gated.removeDefaults() }
        await gated.services.databases.configure { $0.gate = gate }
        let model = gated.state.databases
        model.beginEdit(SampleServices.reportingID)
        let task = try #require(model.saveEditor())
        model.closeEditor()
        #expect(model.newItemAction?.isEnabled == false)
        await gate.open()
        await task.value
        #expect(model.newItemAction?.isEnabled == true)
    }

    @Test("File › New Bucket… opens Add Bucket, and is off while a sheet shows or without RustFS")
    func newBucket() async throws {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        state.navigation.show(.section(.storage))
        let action = try #require(state.storage.newItemAction)
        #expect(action.id == "storage.new")
        #expect(AppCommand.newItem.title(in: state) == "New Bucket…")
        #expect(AppCommand.newItem.isEnabled(in: state))
        AppCommand.newItem.perform(in: state)
        #expect(state.storage.bucketDraft == BucketDraft())
        #expect(!AppCommand.newItem.isEnabled(in: state))
        state.storage.cancelAddBucket()
        await state.storage.stop()?.value
        state.storage.editPorts()
        #expect(state.storage.newItemAction?.isEnabled == false)

        let noRuntime = await launched(
            InMemoryServicePorts(
                databases: InMemoryDatabases(), storage: InMemoryStorage(), mail: InMemoryMail()))
        defer { noRuntime.removeDefaults() }
        #expect(noRuntime.state.storage.newItemAction?.isEnabled == false)
    }

    @Test("Mail has no File › New command")
    func mailHasNoNewItem() async {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        fixture.state.navigation.show(.section(.mail))
        #expect(fixture.state.mail.newItemAction == nil)
        #expect(AppCommand.newItem.title(in: fixture.state) == "New…")
        #expect(!AppCommand.newItem.isEnabled(in: fixture.state))
    }

    @Test("File › New of a service section is off during a quit")
    func newItemOffDuringQuit() async {
        let fixture = await quitting()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        for section in [AppSection.databases, .storage] {
            state.navigation.show(.section(section))
            #expect(!AppCommand.newItem.isEnabled(in: state))
            AppCommand.newItem.perform(in: state)
        }
        #expect(state.databases.sheet == nil)
        #expect(state.storage.bucketDraft == nil)
    }
}

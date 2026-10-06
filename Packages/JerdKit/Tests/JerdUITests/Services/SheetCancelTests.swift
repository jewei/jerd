import Foundation
import JerdDatabases
import JerdMail
import JerdServiceKit
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

/// Cancel in a sheet that saves: it hides the sheet and asks the task to stop, but the feature
/// stays locked until the task ends, and a late result never changes a newer sheet, the
/// selection, or a service. A late failure shows once, as the page banner.
@Suite("Cancel during a sheet save")
@MainActor
struct SheetCancelTests {
    private func launched(
        databases: InMemoryDatabases = InMemoryDatabases(), storage: InMemoryStorage = InMemoryStorage(),
        mail: InMemoryMail = InMemoryMail()
    ) async -> AppFixture {
        let fixture = AppFixture(services: InMemoryServicePorts(databases: databases, storage: storage, mail: mail))
        await fixture.state.launch()
        return fixture
    }

    /// Lets the save run until it waits at the gate.
    private func waitForHold(_ gate: FixtureGate) async {
        for _ in 0..<2_000 where await !gate.isHolding {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func gatedDatabases(failure: String? = nil) async -> (InMemoryDatabases, FixtureGate) {
        let gate = FixtureGate()
        let databases = InMemoryDatabases(
            configuration: SampleServices.databases(.empty), retained: SampleServices.retained)
        await databases.configure {
            $0.gate = gate
            $0.failure = failure
        }
        return (databases, gate)
    }

    // MARK: Databases

    @Test("Cancel during Add keeps the registry locked until the save ends, and the page says why")
    func databaseCancelKeepsLock() async throws {
        let (databases, gate) = await gatedDatabases()
        let fixture = await launched(databases: databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        model.editor?.setPort("3307")
        let task = try #require(model.saveEditor())
        await waitForHold(gate)
        #expect(model.cancelledSaveMessage == nil)
        model.closeEditor()
        #expect(model.sheet == nil)
        #expect(model.editor == nil)
        #expect(!model.canChangeRegistry)
        #expect(model.isBusy)
        #expect(
            model.cancelledSaveMessage == "A cancelled change is still finishing. Add, Edit, and Remove wait for it.")
        model.beginAdd(.postgresql)
        #expect(model.sheet == nil)
        await gate.open()
        await task.value
        #expect(model.canChangeRegistry)
        #expect(model.editorOperation == .idle)
        #expect(model.cancelledSaveMessage == nil)
    }

    @Test("An Add that ends after Cancel does not close a newer sheet, select, or start the service")
    func databaseLateSuccessChangesNothing() async throws {
        let (databases, gate) = await gatedDatabases()
        let fixture = await launched(databases: databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        model.editor?.setPort("3307")
        let task = try #require(model.saveEditor())
        await waitForHold(gate)
        model.closeEditor()
        model.showRetained()
        #expect(model.sheet == .retained)
        await gate.open()
        await task.value
        await waitUntil { !model.isBusy }
        #expect(model.sheet == .retained)
        #expect(fixture.state.navigation.selection(in: .databases) == nil)
        #expect(model.services.map(\.name) == ["MySQL"])
        #expect(await databases.calls.contains { $0.hasPrefix("start") } == false)
        #expect(model.operation == .idle)
    }

    @Test("An Add that fails after Cancel shows the failure once, as the page banner")
    func databaseLateFailureShowsInPage() async throws {
        let (databases, gate) = await gatedDatabases(failure: "Port 3307 is in use by another program.")
        let fixture = await launched(databases: databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        model.editor?.setPort("3307")
        let task = try #require(model.saveEditor())
        await waitForHold(gate)
        model.closeEditor()
        await gate.open()
        await task.value
        #expect(model.operation == .failed(message: "Port 3307 is in use by another program."))
        #expect(model.editorOperation == .idle)
        #expect(model.sheet == nil)
    }

    @Test("A restore that ends after Cancel keeps the lock until then and selects nothing")
    func restoreCancel() async throws {
        let (databases, gate) = await gatedDatabases()
        let fixture = await launched(databases: databases)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginRestore(SampleServices.retained[0])
        let task = try #require(model.saveRestore())
        await waitForHold(gate)
        #expect(model.cancelledSaveMessage == nil)
        model.closeRestore()
        #expect(model.sheet == nil)
        #expect(!model.canChangeRegistry)
        #expect(model.cancelledSaveMessage != nil)
        model.showRetained()
        await gate.open()
        await task.value
        #expect(model.sheet == .retained)
        #expect(fixture.state.navigation.selection(in: .databases) == nil)
        #expect(model.canChangeRegistry)
        #expect(model.cancelledSaveMessage == nil)
    }

    // MARK: Storage

    private func gatedStorage(bucketFailure: String? = nil) async -> (InMemoryStorage, FixtureGate) {
        let gate = FixtureGate()
        let storage = InMemoryStorage(settings: StorageSettings(runtime: SampleServices.storageRuntime))
        await storage.configure {
            $0.gate = gate
            $0.bucketFailure = bucketFailure
        }
        return (storage, gate)
    }

    @Test("Cancel during Add Bucket keeps storage locked, and the late bucket is not selected")
    func bucketCancel() async throws {
        let (storage, gate) = await gatedStorage()
        let fixture = await launched(storage: storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.beginAddBucket()
        model.bucketDraft?.name = "uploads"
        let task = try #require(model.saveBucket())
        await waitForHold(gate)
        #expect(model.cancelledSaveMessage == nil)
        model.cancelAddBucket()
        #expect(model.bucketDraft == nil)
        #expect(!model.canAddBucket)
        #expect(!model.canChange)
        #expect(model.cancelledSaveMessage == "A cancelled change is still finishing. Storage controls wait for it.")
        model.beginAddBucket()
        #expect(model.bucketDraft == nil)
        await gate.open()
        await task.value
        #expect(model.bucketDraft == nil)
        #expect(fixture.state.navigation.selection(in: .storage) == nil)
        #expect(model.bucket(named: "uploads")?.setupComplete == true)
        #expect(model.canAddBucket)
        #expect(model.cancelledSaveMessage == nil)
    }

    @Test("An Add Bucket that fails after Cancel shows the failure as the page banner")
    func bucketLateFailure() async throws {
        let (storage, gate) = await gatedStorage(bucketFailure: "RustFS refused the policy.")
        let fixture = await launched(storage: storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.beginAddBucket()
        model.bucketDraft?.name = "uploads"
        let task = try #require(model.saveBucket())
        await waitForHold(gate)
        model.cancelAddBucket()
        await gate.open()
        await task.value
        #expect(model.operation == .failed(message: "RustFS refused the policy."))
        #expect(model.bucketOperation == .idle)
    }

    @Test("Cancel during a storage port change keeps the lock, and a newer sheet stays open")
    func storagePortsCancel() async throws {
        let (storage, gate) = await gatedStorage()
        let fixture = await launched(storage: storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.editPorts()
        model.portsDraft = PortsDraft(first: "9100", second: "9101")
        let task = try #require(model.savePorts())
        await waitForHold(gate)
        model.cancelPorts()
        #expect(model.portsDraft == nil)
        #expect(!model.canEditPorts)
        #expect(model.cancelledSaveMessage != nil)
        model.editPorts()
        #expect(model.portsDraft == nil)
        await gate.open()
        await task.value
        #expect(model.canEditPorts)
        #expect(model.cancelledSaveMessage == nil)
        model.editPorts()
        #expect(model.portsDraft == PortsDraft(first: 9100, second: 9101))
    }

    @Test("Quit waits for every storage task, also a cancelled bucket save")
    func storageQuitWaitsForCancelledSave() async throws {
        let (storage, gate) = await gatedStorage()
        let fixture = await launched(storage: storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.beginAddBucket()
        model.bucketDraft?.name = "uploads"
        _ = try #require(model.saveBucket())
        await waitForHold(gate)
        model.cancelAddBucket()
        let shutdown = Task { await model.shutdown() }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(await storage.calls.contains("stop") == false)
        await gate.open()
        #expect(await shutdown.value)
        #expect(await storage.calls.last == "stop")
    }

    // MARK: Mail

    @Test("Cancel during a mail port change keeps the lock and says why; a late failure shows in the page")
    func mailPortsCancel() async throws {
        let gate = FixtureGate()
        let mail = InMemoryMail(settings: MailSettings(runtime: SampleServices.mailRuntime), hasData: true)
        await mail.configure {
            $0.gate = gate
            $0.failure = "Port 8030 is in use."
        }
        let fixture = await launched(mail: mail)
        defer { fixture.removeDefaults() }
        let model = fixture.state.mail
        model.editPorts()
        model.portsDraft?.second = "8030"
        let task = try #require(model.savePorts())
        await waitForHold(gate)
        #expect(model.cancelledSaveMessage == nil)
        model.cancelPorts()
        #expect(model.portsDraft == nil)
        #expect(!model.canEditPorts)
        #expect(!model.canStart)
        #expect(model.cancelledSaveMessage == "A cancelled change is still finishing. Mail controls wait for it.")
        model.editPorts()
        #expect(model.portsDraft == nil)
        await gate.open()
        await task.value
        #expect(model.operation == .failed(message: "Port 8030 is in use."))
        #expect(model.portsOperation == .idle)
        #expect(model.canEditPorts)
        #expect(model.cancelledSaveMessage == nil)
    }
}

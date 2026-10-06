import JerdServiceKit
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Storage model")
@MainActor
struct StorageModelTests {
    private func launched(_ storage: InMemoryStorage) async -> AppFixture {
        let fixture = AppFixture(
            services: InMemoryServicePorts(databases: InMemoryDatabases(), storage: storage, mail: InMemoryMail()))
        await fixture.state.launch()
        return fixture
    }

    private func emptyStorage() -> InMemoryStorage {
        InMemoryStorage(settings: StorageSettings(runtime: SampleServices.storageRuntime))
    }

    @Test("Save starts storage, verifies the bucket, closes the sheet, and selects it")
    func addBucket() async {
        let storage = emptyStorage()
        let fixture = await launched(storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.beginAddBucket()
        model.bucketDraft?.name = " uploads "
        await model.saveBucket()?.value
        #expect(await storage.calls.suffix(2) == ["add uploads private", "start"])
        #expect(model.bucketDraft == nil)
        #expect(model.bucket(named: "uploads")?.setupComplete == true)
        #expect(fixture.state.navigation.selection(in: .storage) == .bucket("uploads"))
    }

    @Test("A failed bucket setup stays in the sheet and the bucket stays unfinished")
    func addBucketFailure() async {
        let storage = emptyStorage()
        await storage.configure { $0.bucketFailure = "RustFS refused the policy." }
        let fixture = await launched(storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.beginAddBucket()
        model.bucketDraft = BucketDraft(name: "uploads", publicRead: true)
        await model.saveBucket()?.value
        #expect(model.bucketOperation == .failed(message: "RustFS refused the policy."))
        #expect(model.bucketDraft != nil)
        #expect(model.operation == .idle)
        let bucket = model.bucket(named: "uploads")
        #expect(bucket?.setupComplete == false)
        #expect(bucket.map { model.snapshot.status(of: $0) } == .setupIncomplete)
    }

    @Test("Retry finishes an unfinished bucket")
    func retry() async {
        let storage = InMemoryStorage(
            settings: StorageSettings(runtime: SampleServices.storageRuntime, buckets: SampleServices.buckets))
        let fixture = await launched(storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        let bucket = SampleServices.buckets[2]
        await model.retry(bucket)?.value
        #expect(model.bucket(named: bucket.name)?.setupComplete == true)
        #expect(model.state.isRunning)
    }

    @Test("A key copy never blocks or clears other work")
    func copyDoesNotBlock() async {
        let storage = InMemoryStorage(
            settings: StorageSettings(runtime: SampleServices.storageRuntime), state: .running(pid: 3), hasData: true)
        await storage.configure { $0.stopBehavior = .suspend }
        let fixture = await launched(storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        let stop = model.stop()
        #expect(model.operation.isWorking)
        await model.copySecretKey().value
        #expect(fixture.shell.pasteboard == [SampleServices.credentials.secretKey])
        #expect(model.operation.isWorking)
        stop?.cancel()
    }

    @Test("The Laravel settings name the bucket and the shared keys")
    func copyEnvironment() async {
        let storage = InMemoryStorage(
            settings: StorageSettings(runtime: SampleServices.storageRuntime, buckets: SampleServices.buckets),
            hasData: true)
        let fixture = await launched(storage)
        defer { fixture.removeDefaults() }
        await fixture.state.storage.copyEnvironment(for: SampleServices.buckets[0]).value
        let text = fixture.shell.pasteboard.last ?? ""
        #expect(text.contains("AWS_BUCKET=studio-uploads"))
        #expect(text.contains("AWS_ACCESS_KEY_ID=\(SampleServices.credentials.accessKey)"))
        #expect(fixture.state.clipboard.feedback?.text == "Copied Laravel settings")
    }

    @Test("Missing credentials show once as the page banner")
    func credentialsMissing() async {
        let fixture = await launched(emptyStorage())
        defer { fixture.removeDefaults() }
        await fixture.state.storage.copyAccessKey().value
        #expect(fixture.state.storage.operation.failureMessage == "Start storage once to create its credentials.")
        #expect(fixture.shell.pasteboard.isEmpty)
    }

    @Test("The console opens only while storage runs")
    func console() async {
        let fixture = await launched(emptyStorage())
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.openConsole()
        #expect(fixture.shell.openedURLs.isEmpty)
        await model.start()?.value
        model.openConsole()
        #expect(fixture.shell.openedURLs == [model.settings.consoleURL])
    }

    @Test("Without a runtime, Start and Add stay off and the card says how to continue")
    func noRuntime() async {
        let fixture = await launched(InMemoryStorage())
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        #expect(!model.canStart)
        #expect(!model.canAddBucket)
        #expect(model.summary.summary == "RustFS is not installed. Install it in Runtimes.")
        model.showRuntimes()
        #expect(fixture.state.navigation.dashboardPage == .runtimes)
    }

    @Test("Ports save while stopped and keep the buckets")
    func ports() async {
        let storage = emptyStorage()
        let fixture = await launched(storage)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.editPorts()
        await model.suggestPorts()?.value
        await model.savePorts()?.value
        #expect(model.settings.ports == StoragePorts(api: 9010, console: 9011))
        #expect(model.portsDraft == nil)
    }

    @Test("Quit waits for a failed stop to report it and keeps Jerd open")
    func shutdownFailure() async {
        let storage = InMemoryStorage(
            settings: StorageSettings(runtime: SampleServices.storageRuntime), state: .running(pid: 3))
        await storage.configure { $0.stopBehavior = .fail("Storage is busy.") }
        let fixture = await launched(storage)
        defer { fixture.removeDefaults() }
        #expect(await fixture.state.storage.shutdown() == false)
        #expect(fixture.state.storage.operation == .failed(message: "Storage is busy."))
    }
}

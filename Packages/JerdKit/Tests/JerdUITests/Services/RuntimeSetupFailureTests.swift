import JerdDatabases
import JerdDesign
import JerdMail
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Runtime setup failures")
@MainActor
struct RuntimeSetupFailureTests {
    nonisolated static let reason = "The bundled runtime payloads are missing from this build"

    private func launched(
        databases: InMemoryDatabases = InMemoryDatabases(), storage: InMemoryStorage = InMemoryStorage(),
        mail: InMemoryMail = InMemoryMail()
    ) async -> AppFixture {
        let fixture = AppFixture(
            services: InMemoryServicePorts(databases: databases, storage: storage, mail: mail))
        await fixture.state.launch()
        return fixture
    }

    @Test("Each service reads the failed bundled setup once, after its load")
    func modelsReadTheFailure() async {
        let databases = InMemoryDatabases()
        let storage = InMemoryStorage()
        let mail = InMemoryMail()
        await databases.configure { $0.setupFailure = Self.reason }
        await storage.configure { $0.setupFailure = Self.reason }
        await mail.configure { $0.setupFailure = Self.reason }
        let fixture = await launched(databases: databases, storage: storage, mail: mail)
        defer { fixture.removeDefaults() }
        #expect(fixture.state.databases.runtimeSetupFailure == Self.reason)
        #expect(fixture.state.storage.runtimeSetupFailure == Self.reason)
        #expect(fixture.state.mail.runtimeSetupFailure == Self.reason)
    }

    @Test("Without a failed setup, a missing runtime is information with View Runtimes")
    func missingRuntimeIsInformation() {
        let message = MissingRuntimeBanner.message(copy: MailPageMessages.runtimeCopy, setupFailure: nil)
        #expect(message.kind == .info)
        #expect(message.title == nil)
        #expect(message.text == "Mailpit is not installed. Install it in Runtimes to start the inbox.")
        #expect(message.identifier == "mail.no-runtime")
    }

    @Test("A failed setup is a warning with its reason as a sentence, then the next step")
    func failedSetupIsAWarning() {
        let message = MissingRuntimeBanner.message(copy: StoragePageMessages.runtimeCopy, setupFailure: Self.reason)
        #expect(message.kind == .warning)
        #expect(message.title == "RustFS setup failed")
        #expect(
            message.text
                == "The bundled runtime payloads are missing from this build. Install RustFS in Runtimes to start storage."
        )
        #expect(message.identifier == "storage.runtime-setup-failed")
        let ended = MissingRuntimeBanner.message(copy: MailPageMessages.runtimeCopy, setupFailure: "Disk full!")
        #expect(ended.text == "Disk full! Install Mailpit in Runtimes to start the inbox.")
    }

    @Test("The Databases banner shows only while an engine still has no runtime")
    func databasesBannerFollowsMissingEngines() async {
        let databases = InMemoryDatabases(configuration: SampleServices.databases(.populated))
        await databases.configure { $0.setupFailure = Self.reason }
        let complete = await launched(databases: databases)
        defer { complete.removeDefaults() }
        #expect(complete.state.databases.runtimeSetupFailure == Self.reason)
        #expect(complete.state.databases.visibleRuntimeSetupFailure == nil)

        let partial = InMemoryDatabases(
            configuration: DatabaseConfiguration(runtimes: [SampleServices.mysql], services: []))
        await partial.configure { $0.setupFailure = Self.reason }
        let missing = await launched(databases: partial)
        defer { missing.removeDefaults() }
        #expect(missing.state.databases.visibleRuntimeSetupFailure == Self.reason)
    }

    @Test("A failed settings load shows the load failure, not a setup failure")
    func loadFailureComesFirst() async {
        let mail = InMemoryMail()
        await mail.configure {
            $0.loadFailure = "settings.json is not valid JSON."
            $0.setupFailure = Self.reason
        }
        let fixture = await launched(mail: mail)
        defer { fixture.removeDefaults() }
        #expect(fixture.state.mail.loadState.failureMessage != nil)
        #expect(fixture.state.mail.runtimeSetupFailure == nil)
    }
}

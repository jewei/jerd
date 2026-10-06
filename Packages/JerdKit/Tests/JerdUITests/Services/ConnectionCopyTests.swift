import Foundation
import JerdDatabases
import JerdMail
import JerdServiceKit
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

/// Copy actions of the Connection and Laravel sections.
@Suite("Connection copies")
@MainActor
struct ConnectionCopyTests {
    private func launched(_ ports: InMemoryServicePorts = InMemoryServicePorts(.populated)) async -> AppFixture {
        let fixture = AppFixture(services: ports)
        await fixture.state.launch()
        return fixture
    }

    private func copyable(_ values: [ConnectionValue]) -> [String] {
        values.filter { $0.copy != nil }.map(\.label)
    }

    @Test("Every value that an application needs has a copy button; only descriptions have none")
    func copyButtonsPerRow() async throws {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        let mail = MailConnectionSection.values(fixture.state.mail)
        #expect(copyable(mail) == ["Host", "SMTP port", "Inbox URL"])
        #expect(mail.map(\.label) == ["Host", "SMTP port", "Inbox URL", "Authentication", "Encryption"])
        let storage = fixture.state.storage
        let bucket = try #require(storage.buckets.first)
        let storageValues = StorageConnectionSection.values(storage, bucket: bucket)
        #expect(copyable(storageValues) == ["Endpoint", "Bucket", "Region"])
        #expect(storageValues.last?.label == "Addressing")
        let service = try #require(fixture.state.databases.services.first)
        let databaseValues = DatabaseConnectionSection.values(fixture.state.databases, service: service, engine: .mysql)
        #expect(copyable(databaseValues) == ["Host", "Port", "User", "Database"])
    }

    @Test("The new copy buttons copy their value with a confirmation")
    func newCopies() async throws {
        let fixture = await launched()
        defer { fixture.removeDefaults() }
        MailConnectionSection.values(fixture.state.mail).first?.copy?()
        #expect(fixture.shell.pasteboard.last == "127.0.0.1")
        #expect(fixture.state.clipboard.feedback?.text == "Copied host")
        let bucket = try #require(fixture.state.storage.buckets.first)
        let values = StorageConnectionSection.values(fixture.state.storage, bucket: bucket)
        values.first { $0.label == "Region" }?.copy?()
        #expect(fixture.shell.pasteboard.last == StorageSettings.region)
        #expect(fixture.state.clipboard.feedback?.text == "Copied region")
    }

    @Test("Mail Laravel settings copy only after the load and not during Quit")
    func mailCopyNeedsLoad() async {
        let fixture = AppFixture(services: InMemoryServicePorts(.populated))
        defer { fixture.removeDefaults() }
        let mail = fixture.state.mail
        #expect(!mail.canCopyEnvironment)
        mail.copyEnvironment()
        #expect(fixture.shell.pasteboard.isEmpty)
        await fixture.state.launch()
        #expect(mail.canCopyEnvironment)
        _ = await mail.shutdown()
        #expect(!mail.canCopyEnvironment)
    }

    @Test("A database copy that ends after the user selected another service copies nothing")
    func databaseCopyChecksSelection() async {
        let gate = FixtureGate()
        let ports = InMemoryServicePorts(.populated)
        await ports.databases.configure { $0.connectionGate = gate }
        let fixture = await launched(ports)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        fixture.state.navigation.show(.item(.database(SampleServices.studioID)))
        let copy = model.copyPassword(SampleServices.studioID)
        fixture.state.navigation.show(.item(.database(SampleServices.cacheID)))
        await gate.open()
        await copy.value
        #expect(fixture.shell.pasteboard.isEmpty)
        #expect(fixture.state.clipboard.feedback == nil)
        fixture.state.navigation.show(.item(.database(SampleServices.studioID)))
        await model.copyPassword(SampleServices.studioID).value
        #expect(fixture.shell.pasteboard.last?.hasPrefix("sample-password-") == true)
    }
}

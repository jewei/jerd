import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct ConfigurationStoreTests {
    @Test func anAbsentFileLoadsAsAnEmptyConfigurationWithoutWriting() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        #expect(try await ConfigurationStore(layout: layout).load() == AppConfiguration())
        #expect(isAbsent(layout.configurationFile))
    }

    @Test func saveWritesAPrivateFileAndKeepsThePreviousBytes() async throws {
        let folder = try TemporaryDirectory(" café")
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let store = ConfigurationStore(layout: layout)
        var configuration = Samples.configuration([Samples.site(URL(fileURLWithPath: "/p/app"))])
        try await store.save(configuration)
        let first = try #require(contents(layout.configurationFile))
        #expect(first == (try ConfigurationCodec.encode(configuration)))
        #expect(mode(layout.configurationFile) == 0o600)
        configuration.sites.removeAll()
        try await store.save(configuration)
        #expect(contents(layout.previousConfigurationFile) == first)
        #expect(try await store.load() == configuration)
    }

    @Test(arguments: ["broken json", "{\"schemaVersion\":999}", "{\"schemaVersion\":1}"])
    func corruptDataIsPreservedOnLoadAndSave(_ text: String) async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        try Data(text.utf8).write(to: layout.configurationFile)
        let store = ConfigurationStore(layout: layout)
        await #expect(throws: JerdError.self) { try await store.load() }
        await #expect(throws: JerdError.self) { try await store.save(AppConfiguration()) }
        #expect(contents(layout.configurationFile) == Data(text.utf8))
        #expect(isAbsent(layout.previousConfigurationFile))
    }

    @Test func aCorruptFileReportsThePreservedFileAndTheCause() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        try Data("{\"schemaVersion\":7}".utf8).write(to: layout.configurationFile)
        await #expect(
            throws: JerdError.corrupt(
                "Cannot read the site configuration. The file was preserved. Unsupported configuration version: 7.")
        ) { try await ConfigurationStore(layout: layout).load() }
    }

    @Test func anInvalidConfigurationIsNotSaved() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        var configuration = AppConfiguration()
        configuration.sites = [Samples.site(URL(fileURLWithPath: "/p/a")), Samples.site(URL(fileURLWithPath: "/p/b"))]
        await #expect(throws: JerdError.self) { try await ConfigurationStore(layout: layout).save(configuration) }
        #expect(isAbsent(layout.configurationFile))
    }
}

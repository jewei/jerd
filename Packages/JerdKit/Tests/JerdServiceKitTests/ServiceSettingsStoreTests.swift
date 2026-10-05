import Foundation
import JerdFoundation
import JerdServiceKit
import Testing

@Suite struct ServiceSettingsStoreTests {
    struct Settings: Codable, Equatable, Sendable {
        var schemaVersion = 1
        var path = "/a/b"
        var port: UInt16 = 1_025
    }

    private func store(_ directory: TemporaryDirectory) -> ServiceSettingsStore<Settings> {
        ServiceSettingsStore(
            file: directory.path("settings.json"), previousFile: directory.path("settings.previous.json"),
            sizeLimit: 65_536, name: "mail settings",
            validate: { settings in
                guard settings.port > 1_023 else { throw JerdError.invalid("Bad port.") }
            })
    }

    @Test func aMissingFileLoadsTheDefaultsWithoutWriting() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        #expect(try store(directory).load(orDefault: Settings()) == Settings())
        #expect(!exists(directory.path("settings.json")))
    }

    @Test func aSaveUsesTheSettingsFormatAndKeepsThePreviousBytes() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let store = store(directory)
        try store.save(Settings())
        let first = try #require(contents(directory.path("settings.json")))
        #expect(
            String(decoding: first, as: UTF8.self)
                == "{\n  \"path\" : \"/a/b\",\n  \"port\" : 1025,\n  \"schemaVersion\" : 1\n}")
        try store.save(Settings(port: 2_000))
        #expect(contents(directory.path("settings.previous.json")) == first)
        #expect(try store.load(orDefault: Settings()).port == 2_000)
        #expect(mode(directory.path("settings.json")) == 0o600)
    }

    @Test(arguments: ["", "{\"schemaVersion\":99,\"path\":\"/a\",\"port\":2000}", "{\"path\":\"/a\",\"port\":2000}"])
    func corruptOrUnsupportedSettingsAreNeverReplaced(_ original: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try write(original, to: directory.path("settings.json"))
        let store = store(directory)
        #expect { try store.load(orDefault: Settings()) } throws: { error in
            let error = try #require(error as? JerdError)
            return error.kind == .corrupt
                && error.message.hasPrefix("Cannot read mail settings. The file was preserved.")
        }
        #expect(throws: (any Error).self) { try store.save(Settings()) }
        #expect(text(directory.path("settings.json")) == original)
        #expect(!exists(directory.path("settings.previous.json")))
    }

    @Test func anOperationRuleComparesWithTheSavedSettings() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try store(directory).save(Settings())
        let strict = store(directory).admitting { saved, new in
            guard saved?.path == new.path else { throw JerdError.invalid("The path cannot change.") }
        }
        #expect(throws: JerdError.invalid("The path cannot change.")) { try strict.save(Settings(path: "/c")) }
        try strict.save(Settings(port: 3_000))
        #expect(throws: JerdError.invalid("Bad port.")) { try strict.save(Settings(port: 80)) }
    }
}

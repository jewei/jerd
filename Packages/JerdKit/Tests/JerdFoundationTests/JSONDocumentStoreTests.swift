import Foundation
import JerdFoundation
import Testing

private struct Settings: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var path: String
    var port: UInt16
    var note: String?
}

@Suite struct JSONDocumentStoreTests {
    private func store(_ folder: TemporaryDirectory, format: JSONFileFormat = .settings) -> JSONDocumentStore<Settings>
    {
        JSONDocumentStore(
            file: folder.path("data/settings.json"), previousFile: folder.path("data/settings.previous.json"),
            sizeLimit: 4_096, format: format, name: "mail settings",
            validate: { settings in
                guard settings.port > 1023 else { throw JerdError.invalid("Use a port from 1024 to 65535.") }
            })
    }

    @Test func anAbsentFileLoadsAsNilAndNothingIsWritten() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        #expect(try store(folder).load() == nil)
        #expect(FileProbe.presence(at: folder.path("data")) == .absent)
    }

    @Test func settingsFormatIsPrettySortedWithUnescapedSlashesAndOmitsNil() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let bytes = try store(folder).save(Settings(path: "/a/b", port: 1025))
        let expected = "{\n  \"path\" : \"/a/b\",\n  \"port\" : 1025,\n  \"schemaVersion\" : 1\n}"
        #expect(String(decoding: bytes, as: UTF8.self) == expected)
        #expect(contents(folder.path("data/settings.json")) == bytes)
        #expect(permissions(folder.path("data")) == 0o700)
        #expect(permissions(folder.path("data/settings.json")) == 0o600)
    }

    @Test func compactFormatMatchesTheDefaultEncoder() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let settings = Settings(path: "/a/b", port: 1025)
        let bytes = try store(folder, format: .compact).save(settings)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("\"path\":\"\\/a\\/b\""))
        #expect(!text.contains(" ") && !text.contains("\n"))
        #expect(try JSONDecoder().decode(Settings.self, from: bytes) == settings)
    }

    @Test func aSaveKeepsTheExactPreviousBytesAndTheFirstSaveKeepsNone() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let documents = store(folder)
        try documents.save(Settings(path: "/one", port: 2000))
        #expect(FileProbe.presence(at: folder.path("data/settings.previous.json")) == .absent)
        let handWritten = Data("{ \"schemaVersion\": 1, \"path\": \"/hand\", \"port\": 3000 }".utf8)
        try handWritten.write(to: folder.path("data/settings.json"))
        try documents.save(Settings(path: "/two", port: 4000))
        #expect(contents(folder.path("data/settings.previous.json")) == handWritten)
        #expect(try documents.load() == Settings(path: "/two", port: 4000))
    }

    @Test(arguments: ["broken json", "{\"schemaVersion\":1}", "{\"schemaVersion\":1,\"path\":\"/a\",\"port\":80}", ""])
    func corruptOrInvalidDataIsPreservedOnLoadAndSave(_ text: String) throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("data/settings.json")
        try OwnedDirectory.create(folder.path("data"))
        try Data(text.utf8).write(to: file)
        let documents = store(folder)
        let loadError = try #require(throws: JerdError.self) { try documents.load() }
        #expect(loadError.kind == .corrupt)
        #expect(loadError.message.hasPrefix("Cannot read mail settings. The file was preserved. "))
        #expect(throws: JerdError.self) { try documents.save(Settings(path: "/new", port: 2000)) }
        #expect(contents(file) == Data(text.utf8))
        #expect(FileProbe.presence(at: folder.path("data/settings.previous.json")) == .absent)
    }

    @Test func aDanglingLinkIsCorruptNotAnEmptyDocument() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try OwnedDirectory.create(folder.path("data"))
        let file = folder.path("data/settings.json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: folder.path("gone"))
        #expect(throws: JerdError.self) { try store(folder).load() }
        #expect(throws: JerdError.self) { try store(folder).save(Settings(path: "/a", port: 2000)) }
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil)
    }

    @Test func aFileAboveTheSizeLimitIsCorrupt() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try OwnedDirectory.create(folder.path("data"))
        try Data(repeating: 32, count: 4_097).write(to: folder.path("data/settings.json"))
        #expect(throws: JerdError.self) { try store(folder).load() }
    }

    @Test func aRuleViolationOnSaveChangesNothing() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let documents = store(folder)
        let bytes = try documents.save(Settings(path: "/a", port: 2000))
        #expect(throws: JerdError.invalid("Use a port from 1024 to 65535.")) {
            try documents.save(Settings(path: "/a", port: 80))
        }
        #expect(contents(folder.path("data/settings.json")) == bytes)
    }
}

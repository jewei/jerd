import Foundation
import JerdFoundation
import JerdTestSupport
import Testing
import os

private struct Identity: Codable, Equatable, Sendable {
    let runtimeID: String
}

private struct Registry: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var names: [String]
}

@Suite struct JSONDocumentStoreHookTests {
    @Test func admitSeesTheSavedDocumentAndCanRefuseAChange() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let seen = Seen()
        let store = JSONDocumentStore<Identity>(
            file: folder.path("runtime.json"), sizeLimit: 1_024, format: .compact, name: "the runtime identity",
            admit: { saved, new in
                seen.record(saved)
                if let saved, saved != new { throw JerdError.invalid("The runtime cannot be replaced.") }
            })
        try store.save(Identity(runtimeID: "a"))
        #expect(throws: JerdError.invalid("The runtime cannot be replaced.")) {
            try store.save(Identity(runtimeID: "b"))
        }
        #expect(seen.values == [nil, Identity(runtimeID: "a")])
        #expect(try store.load() == Identity(runtimeID: "a"))
    }

    @Test func aPerOperationRuleAddsToTheStoreRules() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = JSONDocumentStore<Identity>(
            file: folder.path("runtime.json"), sizeLimit: 1_024, format: .compact, name: "the runtime identity",
            admit: { _, new in
                if new.runtimeID.isEmpty { throw JerdError.invalid("Empty.") }
            })
        let replacing = store.admitting { saved, new in
            if let saved, saved.runtimeID != "a", saved != new { throw JerdError.invalid("Only a may be replaced.") }
        }
        try replacing.save(Identity(runtimeID: "a"))
        try replacing.save(Identity(runtimeID: "b"))
        #expect(throws: JerdError.invalid("Only a may be replaced.")) { try replacing.save(Identity(runtimeID: "c")) }
        #expect(throws: JerdError.invalid("Empty.")) { try replacing.save(Identity(runtimeID: "")) }
        #expect(try store.load() == Identity(runtimeID: "b"))
    }

    @Test func versionedDecodingMigratesInMemoryAndRejectsUnknownVersions() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("configuration.json")
        let store = JSONDocumentStore<Registry>(
            file: file, sizeLimit: 1_024, format: .settings, name: "the site configuration",
            decode: { data, decoder in
                switch try SchemaVersion.read(from: data, decoder: decoder) {
                case 0: Registry(schemaVersion: 1, names: [])
                case 1: try decoder.decode(Registry.self, from: data)
                case let version: throw SchemaVersion.unsupported(version)
                }
            })
        let old = Data("{\"schemaVersion\":0,\"sites\":[]}".utf8)
        try old.write(to: file)
        #expect(try store.load() == Registry(schemaVersion: 1, names: []))
        #expect(contents(file) == old)
        try Data("{\"schemaVersion\":999}".utf8).write(to: file)
        #expect(
            throws: JerdError.corrupt(
                "Cannot read the site configuration. The file was preserved. Unsupported format version: 999.")
        ) {
            try store.load()
        }
    }

    @Test func exactBytesAreSavedAndReadBackForHashing() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = JSONDocumentStore<Identity>(
            file: folder.path("credentials.json"), sizeLimit: 1_024, format: .compact, name: "storage credentials")
        let bytes = Data("{ \"runtimeID\" : \"kept spacing\" }".utf8)
        #expect(try store.save(bytes: bytes) == Identity(runtimeID: "kept spacing"))
        let record = try #require(try store.loadRecord())
        #expect(record.bytes == bytes)
        #expect(record.document == Identity(runtimeID: "kept spacing"))
        #expect(throws: JerdError.self) { try store.save(bytes: Data("not json".utf8)) }
        #expect(contents(folder.path("credentials.json")) == bytes)
    }

    @Test func failureDetailsAreShortSentences() throws {
        let decoder = JSONDecoder()
        let missing = try #require(throws: DecodingError.self) {
            try decoder.decode(Identity.self, from: Data("{}".utf8))
        }
        #expect(FailureDetail.describe(missing) == "A required value is missing: runtimeID.")
        let invalid = try #require(throws: DecodingError.self) {
            try decoder.decode(Identity.self, from: Data("x".utf8))
        }
        #expect(FailureDetail.describe(invalid) == "The file does not contain valid JSON.")
        let wrongType = try #require(throws: DecodingError.self) {
            try decoder.decode(Registry.self, from: Data("{\"schemaVersion\":1,\"names\":[1]}".utf8))
        }
        #expect(FailureDetail.describe(wrongType) == "A value has an unexpected type: names[0].")
        #expect(FailureDetail.describe(JerdError.invalid("Plain.")) == "Plain.")
    }
}

/// Collects values that a store hook reports, from any thread.
private final class Seen: Sendable {
    private let storage = OSAllocatedUnfairLock<[Identity?]>(initialState: [])
    var values: [Identity?] { storage.withLock { $0 } }
    func record(_ value: Identity?) { storage.withLock { $0.append(value) } }
}

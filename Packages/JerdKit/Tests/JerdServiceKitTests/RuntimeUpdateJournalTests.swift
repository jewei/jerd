import Foundation
import JerdFoundation
import JerdServiceKit
import Testing

@Suite struct RuntimeUpdateJournalTests {
    static let id = UUID(uuidString: "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")!

    @Test func theJournalOfOlderBuildsDecodesAsVersionOne() throws {
        // Golden bytes as the old ServiceUpdateBackup wrote them (default JSONEncoder, Set as array).
        let old =
            #"{"id":"0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0","names":["settings.json","settings.previous.json","inbox"],"present":["inbox","settings.json"]}"#
        let journal = try JSONDecoder().decode(RuntimeUpdateJournal.self, from: Data(old.utf8))
        #expect(journal.schemaVersion == 1)
        #expect(journal.id == Self.id)
        #expect(journal.names == ["settings.json", "settings.previous.json", "inbox"])
        #expect(Set(journal.present) == ["inbox", "settings.json"])
        #expect(journal.isValid)
    }

    @Test func aNewJournalKeepsEveryOldKeyAndAddsTheVersion() throws {
        let journal = RuntimeUpdateJournal(id: Self.id, names: ["settings.json", "data"], present: ["data"])
        let data = try JSONFileFormat.compact.makeEncoder().encode(journal)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "id", "names", "present"])
        #expect(object["id"] as? String == Self.id.uuidString)
        #expect(object["names"] as? [String] == ["settings.json", "data"])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(!String(decoding: data, as: UTF8.self).contains("\n"))
        #expect(try JSONDecoder().decode(RuntimeUpdateJournal.self, from: data) == journal)
    }

    @Test(arguments: [
        RuntimeUpdateJournal(id: id, names: ["a", "a"], present: []),
        RuntimeUpdateJournal(id: id, names: ["a"], present: ["b"]),
        RuntimeUpdateJournal(id: id, names: ["../data"], present: []),
        RuntimeUpdateJournal(id: id, names: [".."], present: []),
        RuntimeUpdateJournal(id: id, names: [""], present: []),
    ])
    func unsafeOrInconsistentJournalsAreInvalid(_ journal: RuntimeUpdateJournal) {
        #expect(!journal.isValid)
    }

    @Test func anUnknownVersionIsInvalid() throws {
        let future = #"{"schemaVersion":2,"id":"0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0","names":[],"present":[]}"#
        let journal = try JSONDecoder().decode(RuntimeUpdateJournal.self, from: Data(future.utf8))
        #expect(!journal.isValid)
    }
}

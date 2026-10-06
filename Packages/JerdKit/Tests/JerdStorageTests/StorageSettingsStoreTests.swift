import Foundation
import JerdFoundation
import Testing

@testable import JerdStorage

@Suite struct StorageSettingsStoreTests {
    let directory: TemporaryDirectory
    let layout: StorageLayout
    let store: StorageSettingsStore

    init() throws {
        directory = try TemporaryDirectory()
        layout = DataLayout(root: directory.path("Jerd")).storage
        store = StorageSettingsStore(layout: layout)
    }

    @Test(arguments: [
        Data(), Data("{\"schemaVersion\":999,\"apiPort\":9000,\"consolePort\":9001,\"buckets\":[]}".utf8),
        Data(
            "{\"schemaVersion\":1,\"apiPort\":9000,\"consolePort\":9001,\"buckets\":[{\"name\":\"UP\",\"publicRead\":false,\"setupComplete\":true}]}"
                .utf8),
        Data(repeating: 32, count: 1_048_577),
    ])
    func corruptSettingsAreNeverReplaced(_ bytes: Data) throws {
        defer { directory.remove() }
        try OwnedDirectory.create(layout.root)
        try AtomicFile.write(bytes, to: layout.settingsFile)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.save(StorageSettings()) }
        #expect(contents(layout.settingsFile) == bytes)
    }

    @Test func aMissingFileLoadsTheDefaultsAndASaveKeepsThePreviousBytes() throws {
        defer { directory.remove() }
        #expect(try store.load() == StorageSettings())
        #expect(!exists(layout.settingsFile))
        try store.save(StorageSettings())
        let first = try #require(contents(layout.settingsFile))
        try store.save(StorageSettings(buckets: [StorageBucket(name: "app-uploads")]))
        #expect(contents(layout.previousSettingsFile) == first)
        #expect(try store.load().buckets.map(\.name) == ["app-uploads"])
    }

    @Test func theSavedRuntimeChangesOnlyInAnUpdateThatNamesIt() throws {
        defer { directory.remove() }
        let runtime = StorageSettingsTests.runtime
        let other = StorageRuntime(id: "rustfs-2", version: "2.0.0", path: "/runtimes/rustfs-2")
        try store.save(StorageSettings(runtime: runtime))
        #expect(throws: StorageMessages.runtimeNotReplaceable) { try store.save(StorageSettings(runtime: other)) }
        #expect(throws: StorageMessages.runtimeNotReplaceable) { try store.save(StorageSettings()) }
        #expect(try store.load().runtime == runtime)
        try store.save(StorageSettings(runtime: other), replacing: runtime)
        #expect(try store.load().runtime == other)
    }
}

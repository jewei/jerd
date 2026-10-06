import Foundation
import JerdFoundation
import JerdServiceKitTestSupport
import Testing

@testable import JerdMail

@Suite struct MailSettingsStoreTests {
    let directory: TemporaryDirectory
    let layout: MailLayout
    let store: MailSettingsStore

    init() throws {
        directory = try TemporaryDirectory()
        layout = DataLayout(root: directory.path("Jerd")).mail
        store = MailSettingsStore(layout: layout)
    }

    @Test func aMissingFileLoadsTheDefaultsAndWritesNothing() throws {
        #expect(try store.load() == MailSettings())
        #expect(!exists(layout.settingsFile))
        directory.remove()
    }

    @Test(arguments: [
        Data(), Data("{\"schemaVersion\":999,\"smtpPort\":1025,\"webPort\":8025}".utf8),
        Data("{\"schemaVersion\":1,\"smtpPort\":1025,\"webPort\":1025}".utf8),
        Data(repeating: 32, count: 65_537),
    ])
    func corruptSettingsAreNeverReplaced(_ bytes: Data) throws {
        defer { directory.remove() }
        try OwnedDirectory.create(layout.root)
        try AtomicFile.write(bytes, to: layout.settingsFile)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.save(MailSettings()) }
        #expect(contents(layout.settingsFile) == bytes)
        #expect(!exists(layout.previousSettingsFile))
    }

    @Test func aSaveKeepsThePreviousBytes() throws {
        defer { directory.remove() }
        try store.save(MailSettings())
        let first = try #require(contents(layout.settingsFile))
        try store.save(MailSettings(ports: MailPorts(smtp: 2_525, web: 8_026)))
        #expect(contents(layout.previousSettingsFile) == first)
        #expect(try store.load().ports == MailPorts(smtp: 2_525, web: 8_026))
        #expect(mode(layout.settingsFile) == 0o600)
    }

    @Test func theSavedRuntimeChangesOnlyInAnUpdateThatNamesIt() throws {
        defer { directory.remove() }
        let runtime = MailSettingsTests.runtime
        let other = MailRuntime(id: "mailpit-2", version: "2.0.0", path: "/runtimes/mailpit-2")
        try store.save(MailSettings(runtime: runtime))
        #expect(throws: MailMessages.runtimeNotReplaceable) { try store.save(MailSettings(runtime: other)) }
        #expect(throws: MailMessages.runtimeNotReplaceable) { try store.save(MailSettings()) }
        #expect(throws: MailMessages.runtimeNotReplaceable) {
            try store.save(MailSettings(runtime: other), replacing: other)
        }
        #expect(try store.load().runtime == runtime)
        try store.save(MailSettings(runtime: other), replacing: runtime)
        #expect(try store.load().runtime == other)
    }
}

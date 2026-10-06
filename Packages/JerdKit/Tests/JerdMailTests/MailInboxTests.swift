import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import JerdTestSupport
import Testing

@testable import JerdMail

@Suite struct MailInboxTests {
    let directory: TemporaryDirectory
    let layout: MailLayout
    let inbox: MailInbox
    let runtime = MailSettingsTests.runtime
    let other = MailRuntime(id: "mailpit-2", version: "2.0.0", path: "/runtimes/mailpit-2")

    init() throws {
        directory = try TemporaryDirectory(" service kit ü")
        layout = DataLayout(root: directory.path("Jerd")).mail
        try OwnedDirectory.create(layout.root)
        inbox = MailInbox(layout: layout)
    }

    @Test func aNewInboxGetsItsIdentityAndAPrivateEmptyDatabase() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        #expect(try MarkerFile.read(MailRuntime.self, from: layout.runtimeIdentityFile) == runtime)
        #expect(contents(layout.inboxDatabaseFile) == Data())
        #expect(mode(layout.inboxDatabaseFile) == 0o600)
        #expect(mode(layout.inboxDirectory) == 0o700)
        #expect(!exists(layout.initializedMarkerFile))
        try inbox.prepare(for: runtime)
    }

    @Test func anInboxOfAnotherRuntimeIsRefusedAndPreserved() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        try write("messages", to: layout.inboxDatabaseFile)
        #expect(throws: MailMessages.identityMismatch) { try inbox.prepare(for: other) }
        #expect(throws: MailMessages.identityMismatch) { try inbox.validate(for: other) }
        #expect(text(layout.inboxDatabaseFile) == "messages")
    }

    @Test func filesWithoutAnIdentityAreNeverAdopted() throws {
        defer { directory.remove() }
        try write("someone else's mail", to: layout.inboxDatabaseFile)
        #expect(throws: MailMessages.untracked) { try inbox.validate(for: runtime) }
        #expect(throws: MailMessages.untracked) { try inbox.prepare(for: runtime) }
        #expect(!exists(layout.runtimeIdentityFile))
        #expect(text(layout.inboxDatabaseFile) == "someone else's mail")
    }

    @Test func anInitializedInboxWithoutItsDatabaseIsNeverRecreated() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        try inbox.markInitialized(runtime)
        try FileManager.default.removeItem(at: layout.inboxDatabaseFile)
        #expect(throws: MailMessages.initializedMismatch) { try inbox.prepare(for: runtime) }
        #expect(throws: MailMessages.initializedMismatch) { try inbox.validate(for: runtime) }
        #expect(!exists(layout.inboxDatabaseFile))
    }

    /// The compact marker format has no stable key order, so an equal marker is never written again.
    @Test func aStartWithAnUnchangedMarkerKeepsTheSavedFile() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        try inbox.markInitialized(runtime)
        let saved = inode(layout.initializedMarkerFile)
        let bytes = contents(layout.initializedMarkerFile)
        try inbox.prepare(for: runtime)
        try inbox.markInitialized(runtime)
        #expect(inode(layout.initializedMarkerFile) == saved)
        #expect(contents(layout.initializedMarkerFile) == bytes)
        try inbox.adopt(other)
        #expect(inode(layout.initializedMarkerFile) != saved)
        #expect(try MarkerFile.read(MailRuntime.self, from: layout.initializedMarkerFile) == other)
    }

    @Test func anInitializedMarkerOfAnotherRuntimeIsRefused() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        try inbox.markInitialized(other)
        #expect(throws: MailMessages.initializedMismatch) { try inbox.prepare(for: runtime) }
    }

    @Test func aDatabaseLinkIsRefused() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        let target = directory.path("elsewhere.sqlite")
        try write("outside", to: target)
        try FileManager.default.removeItem(at: layout.inboxDatabaseFile)
        try FileManager.default.createSymbolicLink(at: layout.inboxDatabaseFile, withDestinationURL: target)
        #expect(throws: MailMessages.databaseNotRegular) { try inbox.prepare(for: runtime) }
        #expect(throws: MailMessages.databaseNotRegular) { try inbox.validate(for: runtime) }
        #expect(text(target) == "outside")
    }

    /// A hard link would make Mailpit write into, and Jerd change the mode of, a file elsewhere.
    @Test func aHardLinkedDatabaseIsRefusedAndTheOtherFileKeepsItsMode() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        let target = directory.path("elsewhere.sqlite")
        try write("outside", to: target)
        chmod(target.path, 0o644)
        try FileManager.default.removeItem(at: layout.inboxDatabaseFile)
        try FileManager.default.linkItem(at: target, to: layout.inboxDatabaseFile)
        #expect(throws: MailMessages.databaseNotRegular) { try inbox.prepare(for: runtime) }
        #expect(throws: MailMessages.databaseNotRegular) { try inbox.validate(for: runtime) }
        #expect(text(target) == "outside" && mode(target) == 0o644)
    }

    @Test func anExistingDatabaseKeepsItsBytesAndBecomesPrivate() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        try write("captured", to: layout.inboxDatabaseFile)
        chmod(layout.inboxDatabaseFile.path, 0o644)
        try inbox.prepare(for: runtime)
        #expect(text(layout.inboxDatabaseFile) == "captured")
        #expect(mode(layout.inboxDatabaseFile) == 0o600)
    }

    @Test func validationBeforeAnUpdateWritesNothing() throws {
        defer { directory.remove() }
        try inbox.validate(for: runtime)
        #expect(!exists(layout.inboxDirectory))
        try OwnedDirectory.create(layout.inboxDirectory)
        try inbox.validate(for: runtime)
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.inboxDirectory.path).isEmpty)
    }

    @Test func adoptionMovesOnlyTheMarkersThatExist() throws {
        defer { directory.remove() }
        try inbox.prepare(for: runtime)
        try inbox.adopt(other)
        #expect(try MarkerFile.read(MailRuntime.self, from: layout.runtimeIdentityFile) == other)
        #expect(!exists(layout.initializedMarkerFile))
        try inbox.markInitialized(other)
        try inbox.adopt(runtime)
        #expect(try MarkerFile.read(MailRuntime.self, from: layout.initializedMarkerFile) == runtime)
    }
}

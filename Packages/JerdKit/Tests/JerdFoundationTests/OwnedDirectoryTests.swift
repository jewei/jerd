import Darwin
import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@Suite struct OwnedDirectoryTests {
    @Test func createMakesEveryNewFolderPrivate() throws {
        let folder = try TemporaryDirectory(" owned ü")
        defer { folder.remove() }
        let target = folder.path("a/b/c")
        try OwnedDirectory.create(target)
        for path in ["a", "a/b", "a/b/c"] { #expect(permissions(folder.path(path)) == 0o700) }
    }

    @Test func createTightensTheTargetButNeverChangesAnExistingParent() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let parent = folder.path("parent")
        let target = parent.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        chmod(parent.path, 0o755)
        chmod(target.path, 0o755)
        try OwnedDirectory.create(target)
        #expect(permissions(target) == 0o700)
        #expect(permissions(parent) == 0o755)
    }

    @Test func createRefusesALinkOrAFileAtTheTarget() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let elsewhere = folder.path("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: false)
        chmod(elsewhere.path, 0o755)
        let link = folder.path("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        #expect(throws: JerdError.invalid("Expected an app-owned directory: \(link.path)")) {
            try OwnedDirectory.create(link)
        }
        #expect(permissions(elsewhere) == 0o755)
        let file = folder.path("file")
        try Data().write(to: file)
        #expect(throws: JerdError.self) { try OwnedDirectory.create(file) }
    }

    @Test func aFolderOfAnotherOwnerIsRefusedAndNotChanged() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let target = folder.path("foreign")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        chmod(target.path, 0o755)
        #expect(throws: JerdError.self) { try OwnedDirectory.create(target, owner: geteuid() + 1) }
        #expect(permissions(target) == 0o755)
    }

    @Test func createWithinARootRefusesALinkedComponent() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let root = folder.path("root")
        try OwnedDirectory.create(root)
        try OwnedDirectory.create(root.appendingPathComponent("mail/runtime-backups"), within: root)
        #expect(permissions(root.appendingPathComponent("mail/runtime-backups")) == 0o700)
        let elsewhere = folder.path("elsewhere")
        try OwnedDirectory.create(elsewhere)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("storage"), withDestinationURL: elsewhere)
        #expect(throws: JerdError.self) {
            try OwnedDirectory.create(root.appendingPathComponent("storage/data"), within: root)
        }
        #expect(FileProbe.presence(at: elsewhere.appendingPathComponent("data")) == .absent)
    }

    @Test func requireContainedAcceptsOwnedFoldersAndRejectsEscapesAndLinks() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let root = folder.path("root")
        try OwnedDirectory.create(root.appendingPathComponent("a/b"))
        try OwnedDirectory.requireContained(root.appendingPathComponent("a/b"), in: root)
        try OwnedDirectory.requireContained(root, in: root)
        let escape = root.appendingPathComponent("a/../../outside")
        #expect(throws: JerdError.invalid("The directory \(escape.path) is outside Jerd's data folder.")) {
            try OwnedDirectory.requireContained(escape, in: root)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("a/link"), withDestinationURL: root)
        #expect(throws: JerdError.self) {
            try OwnedDirectory.requireContained(root.appendingPathComponent("a/link/a"), in: root)
        }
        #expect(throws: JerdError.self) {
            try OwnedDirectory.requireContained(root.appendingPathComponent("a/b"), in: root, owner: geteuid() + 1)
        }
    }
}

/// Roots that the system reaches through a link, such as `/tmp` (a link to `/private/tmp`).
@Suite struct OwnedDirectoryCanonicalRootTests {
    /// A private folder below `/private/tmp`, named in both the `/private/tmp` and the `/tmp` form.
    private struct SharedTemporaryFolder {
        let name = "jerd-tests-\(UUID().uuidString)"
        var privateForm: URL { URL(filePath: "/private/tmp/\(name)", directoryHint: .isDirectory) }
        var shortForm: URL { URL(filePath: "/tmp/\(name)", directoryHint: .isDirectory) }

        init() throws { try OwnedDirectory.create(URL(filePath: "/private/tmp/\(name)")) }
        func remove() { try? FileManager.default.removeItem(at: privateForm) }
    }

    @Test func aRootUnderPrivateTmpAcceptsNewAndExistingFolders() throws {
        let folder = try SharedTemporaryFolder()
        defer { folder.remove() }
        let root = folder.privateForm.appending(path: "root")
        try OwnedDirectory.create(root)
        try OwnedDirectory.create(root.appending(path: "mail/data"), within: root)
        try OwnedDirectory.requireContained(root.appending(path: "mail/data"), in: root)
        #expect(permissions(root.appending(path: "mail")) == 0o700)
    }

    @Test func theTmpAndPrivateTmpFormsNameTheSameRoot() throws {
        let folder = try SharedTemporaryFolder()
        defer { folder.remove() }
        let privateRoot = folder.privateForm.appending(path: "root")
        let shortRoot = folder.shortForm.appending(path: "root")
        try OwnedDirectory.create(privateRoot)
        try OwnedDirectory.create(shortRoot.appending(path: "a/new"), within: privateRoot)
        try OwnedDirectory.create(privateRoot.appending(path: "b/new"), within: shortRoot)
        try OwnedDirectory.requireContained(shortRoot.appending(path: "a/new"), in: privateRoot)
        try OwnedDirectory.requireContained(privateRoot.appending(path: "b/new"), in: shortRoot)
    }

    @Test func aLinkedRootIsResolvedButALinkBelowItIsStillRefused() throws {
        let folder = try SharedTemporaryFolder()
        defer { folder.remove() }
        let real = folder.privateForm.appending(path: "real")
        let root = folder.shortForm.appending(path: "linked-root")
        try OwnedDirectory.create(real)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: real)
        try OwnedDirectory.create(root.appending(path: "a"), within: root)
        try OwnedDirectory.requireContained(real.appending(path: "a"), in: root)
        try OwnedDirectory.requireContained(root.appending(path: "a"), in: real)
        let outside = folder.privateForm.appending(path: "outside")
        try OwnedDirectory.create(outside)
        try FileManager.default.createSymbolicLink(at: real.appending(path: "a/link"), withDestinationURL: outside)
        #expect(throws: JerdError.self) {
            try OwnedDirectory.requireContained(root.appending(path: "a/link"), in: root)
        }
        #expect(throws: JerdError.self) {
            try OwnedDirectory.create(root.appending(path: "a/link/new"), within: root)
        }
        #expect(FileProbe.presence(at: outside.appending(path: "new")) == .absent)
        #expect(throws: JerdError.self) { try OwnedDirectory.requireContained(outside, in: root) }
    }
}

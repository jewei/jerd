import Foundation
import JerdArchive
import JerdFoundation
import JerdTestSupport
import Testing

@Suite struct ContainedTreeCopierTests {
    /// A source tree `root/Versions/18/{bin,lib}` with one executable and one library.
    private func makeTree(_ folder: TemporaryDirectory) throws -> URL {
        let version = folder.path("root/Versions/18")
        try FileManager.default.createDirectory(
            at: version.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: version.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try Data("server".utf8).write(to: version.appendingPathComponent("bin/postgres"))
        chmod(version.appendingPathComponent("bin/postgres").path, 0o755)
        try Data("library".utf8).write(to: version.appendingPathComponent("lib/libpq.dylib"))
        try Data("static".utf8).write(to: version.appendingPathComponent("lib/libpq.a"))
        return version
    }

    @Test func copiesSelectedFilesWithPrivateModesAndSkipsOthers() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        let target = folder.path("payload/lib")
        try ContainedTreeCopier.copy(from: version.appendingPathComponent("lib"), to: target, root: version) {
            $0.components.last?.hasSuffix(".a") == false
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path) == ["libpq.dylib"])
        #expect(permissions(target) == 0o700 && permissions(target.appendingPathComponent("libpq.dylib")) == 0o600)
        try ContainedTreeCopier.copy(
            from: version.appendingPathComponent("bin"), to: folder.path("payload/bin"), root: version
        ) { _ in true }
        #expect(permissions(folder.path("payload/bin/postgres")) == 0o700)
    }

    @Test func selectorReceivesPathsRelativeToTheSource() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        var seen: [String] = []
        try ContainedTreeCopier.copy(from: version, to: folder.path("payload"), root: version) {
            seen.append($0.string)
            return false
        }
        #expect(seen == ["bin/postgres", "lib/libpq.a", "lib/libpq.dylib"])
    }

    @Test func linksInsideTheRootBecomeRegularFiles() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        try FileManager.default.createSymbolicLink(
            atPath: version.appendingPathComponent("lib/libpq.5.dylib").path, withDestinationPath: "libpq.dylib")
        try ContainedTreeCopier.copy(
            from: version.appendingPathComponent("lib"), to: folder.path("payload"), root: version
        ) { _ in true }
        let copy = folder.path("payload/libpq.5.dylib")
        #expect(try copy.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
        #expect(contents(copy) == Data("library".utf8))
    }

    @Test func linkThatLeavesTheRootIsRefusedEvenWhenUnselected() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        try Data("secret".utf8).write(to: folder.path("outside"))
        try FileManager.default.createSymbolicLink(
            atPath: version.appendingPathComponent("lib/escape").path, withDestinationPath: folder.path("outside").path)
        #expect(throws: ArchiveFailure.treeLinkLeavesRoot) {
            try ContainedTreeCopier.copy(from: version, to: folder.path("payload"), root: version) { _ in false }
        }
        #expect(FileProbe.presence(at: folder.path("payload/lib/escape")) == .absent)
    }

    @Test func folderLinkCycleIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        try FileManager.default.createSymbolicLink(
            atPath: version.appendingPathComponent("lib/loop").path, withDestinationPath: "..")
        #expect(throws: ArchiveFailure.treeCycle) {
            try ContainedTreeCopier.copy(from: version, to: folder.path("payload"), root: version) { _ in true }
        }
    }

    @Test func treeWithTooManyNodesIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        // Nodes: Versions/18, bin, postgres, lib, libpq.a, libpq.dylib.
        #expect(throws: ArchiveFailure.treeTooManyFiles) {
            try ContainedTreeCopier.copy(from: version, to: folder.path("a"), root: version, nodeLimit: 5) { _ in true }
        }
        try ContainedTreeCopier.copy(from: version, to: folder.path("b"), root: version, nodeLimit: 6) { _ in true }
    }

    @Test func selectedNodeThatIsNotARegularFileIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        #expect(mkfifo(version.appendingPathComponent("bin/fifo").path, 0o600) == 0)
        #expect(throws: ArchiveFailure.treeInvalidFile) {
            try ContainedTreeCopier.copy(from: version, to: folder.path("payload"), root: version) { _ in true }
        }
        try ContainedTreeCopier.copy(from: version, to: folder.path("other"), root: version) { $0.string != "bin/fifo" }
    }

    @Test func singleFileSourceIsCopiedToTheDestinationPath() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let version = try makeTree(folder)
        let target = folder.path("payload/server")
        try ContainedTreeCopier.copy(from: version.appendingPathComponent("bin/postgres"), to: target, root: version) {
            $0.string == "postgres"
        }
        #expect(contents(target) == Data("server".utf8))
    }
}

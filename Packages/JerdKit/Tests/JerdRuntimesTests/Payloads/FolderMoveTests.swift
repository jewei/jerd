import Foundation
import JerdFoundation
import JerdRuntimes
import Testing

@Suite struct FolderMoveTests {
    @Test func theMoveRenamesTheSourceToAFreeTarget() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try folder.write("new", to: "source/file")
        try FolderMove.withoutReplacing(folder.path("source"), to: folder.path("target"))
        #expect(try String(contentsOf: folder.path("target/file"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: folder.path("source").path))
    }

    /// An existing folder, for example a corrupt runtime, is preserved and never replaced.
    @Test func anExistingTargetIsPreservedAndTheSourceStays() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try folder.write("new", to: "source/file")
        try folder.write("old", to: "php-8.5.11-arm64/marker")
        let target = folder.path("php-8.5.11-arm64")
        #expect(throws: JerdError.invalid("The runtime folder php-8.5.11-arm64 already exists. It was preserved.")) {
            try FolderMove.withoutReplacing(folder.path("source"), to: target)
        }
        #expect(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8) == "old")
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("file").path))
        #expect(try String(contentsOf: folder.path("source/file"), encoding: .utf8) == "new")
    }

    @Test func aMissingParentIsUnavailable() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try folder.write("new", to: "source/file")
        let error = #expect(throws: JerdError.self) {
            try FolderMove.withoutReplacing(folder.path("source"), to: folder.path("missing/target"))
        }
        #expect(error?.kind == .unavailable)
        #expect(FileManager.default.fileExists(atPath: folder.path("source/file").path))
    }
}

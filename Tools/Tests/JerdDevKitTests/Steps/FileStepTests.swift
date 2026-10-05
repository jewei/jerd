import Foundation
import Testing

@testable import JerdDevKit

/// Steps that work on files, in a temporary repository folder.
@Suite("File steps")
struct FileStepTests {
    @Test("clean prints the folders first, then removes only build folders")
    func cleanRemovesBuildFolders() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.write("x", to: ".build/xcode/a", in: root)
        try TestFixtures.write("x", to: ".build/SourcePackages/b", in: root)
        try TestFixtures.write("x", to: "Tools/.build/c", in: root)
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: Repository(root: root), output: output)
        try CleanStep.run(context, all: false)
        let manager = FileManager.default
        #expect(!manager.fileExists(atPath: root.appending(path: ".build/xcode").path))
        #expect(!manager.fileExists(atPath: root.appending(path: "Tools/.build").path))
        #expect(manager.fileExists(atPath: root.appending(path: ".build/SourcePackages/b").path))
        #expect(
            output.standardOutput.contains("These folders will be removed:\n      .build/xcode\n      Tools/.build\n"))
    }

    @Test("clean with nothing to remove succeeds")
    func cleanWithNothing() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = RecordingTextOutput()
        try CleanStep.run(TestFixtures.context(repository: Repository(root: root), output: output), all: true)
        #expect(output.standardOutput == "    ok: Nothing to remove.\n")
    }

    @Test("lists files below a folder and skips build folders and symbolic links")
    func listsFiles() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.write("a", to: "Docs/A.md", in: root)
        try TestFixtures.write("b", to: "Docs/Sub/B.md", in: root)
        try TestFixtures.write("c", to: "Docs/.build/C.md", in: root)
        try TestFixtures.write("d", to: "Docs/D.txt", in: root)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "Docs/Link.md").path, withDestinationPath: "A.md")
        let paths = try FileTree.relativeFilePaths(under: root.appending(path: "Docs"), pathExtension: "md")
        #expect(paths == ["A.md", "Sub/B.md"])
    }

    @Test("copies listed files to the same paths and skips deleted ones")
    func copiesFiles() throws {
        let source = try TestFixtures.temporaryFolder()
        let destination = try TestFixtures.temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }
        try TestFixtures.write("spec", to: "project.yml", in: source)
        try TestFixtures.write("app", to: "Apps/Jerd/App.swift", in: source)
        try FileTree.copy(["project.yml", "Apps/Jerd/App.swift", "Deleted.swift"], from: source, to: destination)
        #expect(
            try FileTree.readFiles(under: destination) == [
                "project.yml": Data("spec".utf8), "Apps/Jerd/App.swift": Data("app".utf8),
            ])
    }

    @Test("Markdown policy files are root documents, Docs, Tools, Apps, and module READMEs, without links")
    func findsMarkdownFiles() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.write("a", to: "AGENTS.md", in: root)
        try TestFixtures.write("b", to: "Docs/Build.md", in: root)
        try TestFixtures.write("c", to: "Tools/README.md", in: root)
        try TestFixtures.write("d", to: "Tools/.build/checkouts/x/README.md", in: root)
        try TestFixtures.write("e", to: "Apps/Notes.md", in: root)
        try TestFixtures.write("f", to: "Packages/JerdKit/Sources/JerdWeb/README.md", in: root)
        try TestFixtures.write("g", to: "Runtimes/Development/vendor/x/README.md", in: root)
        try FileManager.default.createSymbolicLink(
            atPath: root.appending(path: "CLAUDE.md").path, withDestinationPath: "AGENTS.md")
        let files = try RepositoryPolicy.markdownFiles(in: Repository(root: root))
        #expect(
            files == [
                "AGENTS.md", "Docs/Build.md", "Tools/README.md", "Apps/Notes.md",
                "Packages/JerdKit/Sources/JerdWeb/README.md",
            ])
    }

    @Test("the live link lookup compares the exact letter case of every component")
    func comparesExactCase() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try TestFixtures.write("# Title", to: "Docs/Architecture.md", in: root)
        let files = RepositoryFiles(repository: Repository(root: root))
        #expect(files.exists("Docs/Architecture.md"))
        #expect(files.exists("Docs"))
        #expect(!files.exists("docs/Architecture.md"))
        #expect(!files.exists("Docs/architecture.md"))
        #expect(files.markdown(at: "Docs/Architecture.md") == "# Title")
    }

    @Test("a policy whose file is missing reports the file and fails the step")
    func policyReportsMissingFile() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: Repository(root: root), output: output)
        let policy = try #require(RepositoryPolicy.all.first)
        #expect(throws: DevFailure.checkFailed("These policies failed: Sparkle keys in Info.plist.")) {
            try PolicyStep.run(context, policies: [policy])
        }
        #expect(output.standardError.contains("Apps/Jerd/Resources/Info.plist is missing or cannot be read."))
    }
}

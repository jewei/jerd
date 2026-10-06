import Foundation
import SwiftUI
import Testing

@testable import JerdSnapshotSupport

@Suite("Snapshot command")
@MainActor
struct SnapshotCommandTests {
    private let tiny = SnapshotSize(name: "tiny", width: 16, height: 12)

    private func catalog(_ names: [String], appearances: [SnapshotAppearance] = [.light]) -> SnapshotCatalog {
        var catalog = SnapshotCatalog()
        for name in names {
            catalog.add(name, sizes: [tiny], appearances: appearances, chrome: .content) { Color.green }
        }
        return catalog
    }

    /// A new folder for one test. The test removes it in a `defer` (review final-domain-r1 L2).
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "jerd-snapshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func files(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    @Test("An unknown option is a usage error with exit status 2")
    func unknownOptionIsUsageError() async {
        let host = RecordingSnapshotHost()
        #expect(await SnapshotCommand(catalog: catalog(["a"]), host: host).run(arguments: ["--colour"]) == 2)
        #expect(host.errors.first?.contains("--colour") == true)
        #expect(host.preparedContrast.isEmpty)
    }

    @Test("A page name that matches nothing is a usage error with exit status 2")
    func unknownPageIsUsageError() async {
        let host = RecordingSnapshotHost()
        #expect(await SnapshotCommand(catalog: catalog(["a"]), host: host).run(arguments: ["mail"]) == 2)
        #expect(host.errors == ["No snapshot matches mail. Use --list to see the names."])
    }

    @Test("Duplicate catalog names fail with exit status 1 before rendering")
    func duplicateNamesFail() async {
        let host = RecordingSnapshotHost()
        #expect(await SnapshotCommand(catalog: catalog(["a", "a"]), host: host).run(arguments: ["--list"]) == 1)
        #expect(host.preparedContrast.isEmpty)
    }

    @Test("List prints the selected names and sizes without rendering")
    func listsEntries() async {
        let host = RecordingSnapshotHost()
        #expect(await SnapshotCommand(catalog: catalog(["a", "b"]), host: host).run(arguments: ["--list", "b"]) == 0)
        #expect(host.output == ["b\ttiny 16×12"])
        #expect(host.preparedContrast.isEmpty)
    }

    @Test("A positional page name renders only that page")
    func rendersOnePage() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let host = RecordingSnapshotHost()
        let status = await SnapshotCommand(catalog: catalog(["a", "b"]), host: host)
            .run(arguments: ["--output", folder.path(percentEncoded: false), "b"])
        #expect(status == 0)
        #expect(host.preparedContrast == [.standard])
        #expect(try files(in: folder) == ["b-light-tiny.png"])
    }

    @Test("A full run removes stale PNG files and keeps other files")
    func fullRunRemovesStaleFiles() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["old-light-tiny.png", "notes.txt"] {
            try Data([1]).write(to: folder.appending(path: name))
        }
        let host = RecordingSnapshotHost()
        let status = await SnapshotCommand(catalog: catalog(["a"]), host: host)
            .run(arguments: ["--output", folder.path(percentEncoded: false)])
        #expect(status == 0)
        #expect(try files(in: folder) == ["a-light-tiny.png", "notes.txt"])
        #expect(host.output.last == "Removed 1 stale snapshots: old-light-tiny.png")
    }

    @Test("A filtered run keeps the files of other pages")
    func filteredRunKeepsFiles() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([1]).write(to: folder.appending(path: "old-light-tiny.png"))
        let status = await SnapshotCommand(catalog: catalog(["a"]), host: RecordingSnapshotHost())
            .run(arguments: ["--output", folder.path(percentEncoded: false), "a"])
        #expect(status == 0)
        #expect(try files(in: folder) == ["a-light-tiny.png", "old-light-tiny.png"])
    }

    @Test("Contrast variants render in a second process with the contrast pass option")
    func startsContrastPass() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.path(percentEncoded: false)
        let host = RecordingSnapshotHost()
        var catalog = catalog(["plain"])
        catalog.add("contrast", sizes: [tiny], appearances: SnapshotAppearance.allCases, chrome: .content) {
            Color.green
        }
        #expect(await SnapshotCommand(catalog: catalog, host: host).run(arguments: ["--output", path]) == 0)
        #expect(host.contrastPassArguments == [["--contrast-pass", "--output", path, "contrast"]])
        #expect(try files(in: folder) == ["contrast-dark-tiny.png", "contrast-light-tiny.png", "plain-light-tiny.png"])
    }

    @Test("A failed contrast pass fails the run with exit status 1")
    func failedContrastPassFails() async throws {
        let host = RecordingSnapshotHost()
        host.contrastPassStatus = 1
        let catalog = catalog(["contrast"], appearances: [.light, .lightContrast])
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let status = await SnapshotCommand(catalog: catalog, host: host)
            .run(arguments: ["--output", folder.path(percentEncoded: false)])
        #expect(status == 1)
        #expect(host.errors == ["The Increase Contrast pass failed with exit status 1."])
    }

    @Test("The contrast pass prepares Increase Contrast and does not start another pass")
    func contrastPassPreparesProcess() async throws {
        let host = RecordingSnapshotHost()
        let catalog = catalog(["contrast"], appearances: [.light, .lightContrast])
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let status = await SnapshotCommand(catalog: catalog, host: host)
            .run(arguments: ["--contrast-pass", "--output", folder.path(percentEncoded: false)])
        // This test process has Increase Contrast off, so the renderer refuses the contrast file.
        #expect(status == 1)
        #expect(host.preparedContrast == [.increased])
        #expect(host.contrastPassArguments.isEmpty)
        #expect(host.errors.first?.contains("contrast-light-contrast-tiny.png") == true)
    }
}

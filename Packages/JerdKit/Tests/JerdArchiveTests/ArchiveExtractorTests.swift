import Foundation
import JerdArchive
import JerdFoundation
import JerdTestSupport
import Testing

@Suite struct ArchiveExtractorTests {
    private func extract(
        _ tar: TarBuilder, in folder: TemporaryDirectory, policy: ExtractionPolicy = ExtractionPolicy(stripsRoot: true)
    ) throws -> ExtractionReport {
        let archive = folder.path("archive-\(UUID().uuidString).tar")
        try tar.write(to: archive)
        return try ArchiveExtractor.extract(archive, to: folder.path("out"), policy: policy)
    }

    @Test func internalLinksBecomeRegularCopiesOfTheirTarget() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/bin/tool", "hello", mode: "0000755")
        tar.symlink("root/bin/alias", to: "tool")
        tar.hardlink("root/bin/hard", to: "root/bin/tool")
        let report = try extract(tar, in: folder)
        #expect(report.files.map(\.string) == ["bin/alias", "bin/hard", "bin/tool"])
        #expect(report.outputBytes == 15)
        for name in ["tool", "alias", "hard"] {
            let file = folder.path("out/bin/\(name)")
            #expect(contents(file) == Data("hello".utf8))
            #expect(try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)
            #expect(permissions(file) == 0o700)
        }
        #expect(permissions(folder.path("out")) == 0o700 && permissions(folder.path("out/bin")) == 0o700)
    }

    @Test(arguments: 0..<7)
    func unsafeArchivesAreRefused(_ index: Int) throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        switch index {
        case 0: tar.file("../escape")
        case 1: tar.file("/absolute")
        case 2: tar.symlink("root/link", to: "../../escape")
        case 3: tar.hardlink("root/link", to: "/tmp/escape")
        case 4: tar.special("root/fifo", type: "6")
        case 5:
            tar.symlink("root/a", to: "b")
            tar.symlink("root/b", to: "a")
        default:
            tar.file("root/file")
            tar.file("root/FILE")
        }
        #expect(throws: JerdError.self) { try extract(tar, in: folder) }
        #expect(
            FileProbe.presence(at: folder.url.deletingLastPathComponent().appendingPathComponent("escape")) == .absent)
    }

    @Test func linkCopiesCountAgainstTheOutputLimit() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/file", bytes: 10)
        tar.symlink("root/alias", to: "file")
        tar.symlink("root/chain", to: "alias")
        #expect(throws: ArchiveFailure.outputTooLargeAfterLinks) {
            try extract(tar, in: folder, policy: ExtractionPolicy(stripsRoot: true, outputLimit: 29))
        }
        let fits = try TemporaryDirectory()
        defer { fits.remove() }
        _ = try extract(tar, in: fits, policy: ExtractionPolicy(stripsRoot: true, outputLimit: 30))
        #expect(contents(fits.path("out/chain"))?.count == 10)
    }

    @Test func outputLimitIgnoresUnselectedEntries() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/large", bytes: 1_000)
        tar.file("root/small", bytes: 10)
        let policy = ExtractionPolicy(stripsRoot: true, outputLimit: 10, selects: { $0.string == "small" })
        #expect(try extract(tar, in: folder, policy: policy).files.map(\.string) == ["small"])
        #expect(FileProbe.presence(at: folder.path("out/large")) == .absent)
    }

    @Test func onlySelectedFilesAreWritten() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.folder("root/")
        tar.file("root/keep", "a")
        tar.file("root/drop", "b")
        tar.symlink("root/drop-link", to: "drop")
        let report = try extract(tar, in: folder, policy: ExtractionPolicy(stripsRoot: true) { $0.string == "keep" })
        #expect(report.files.map(\.string) == ["keep"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path("out").path) == ["keep"])
    }

    @Test func selectedLinkToAnUnselectedFileIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/target", "a")
        tar.symlink("root/link", to: "target")
        #expect(throws: ArchiveFailure.linkTargetMissing) {
            try extract(tar, in: folder, policy: ExtractionPolicy(stripsRoot: true) { $0.string == "link" })
        }
    }

    @Test func perEntrySizeLimitAppliesToUnselectedEntries() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/large", bytes: 100)
        var policy = ExtractionPolicy(stripsRoot: true) { _ in false }
        policy.fileSizeLimit = 99
        #expect(throws: ArchiveFailure.fileTooLarge) { try extract(tar, in: folder, policy: policy) }
    }

    @Test func entryCountLimitCountsEveryEntry() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        for index in 0..<4 { tar.file("root/\(index)") }
        var policy = ExtractionPolicy(stripsRoot: true) { _ in false }
        policy.entryLimit = 3
        #expect(throws: ArchiveFailure.tooManyEntries) { try extract(tar, in: folder, policy: policy) }
    }

    @Test func archivesWithTwoRootsOrAFileRootAreRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var two = TarBuilder()
        two.file("one/a")
        two.file("two/b")
        #expect(throws: ArchiveFailure.moreThanOneRoot) { try extract(two, in: folder) }
        var fileRoot = TarBuilder()
        fileRoot.file("root")
        #expect(throws: ArchiveFailure.rootNotDirectory) { try extract(fileRoot, in: folder) }
    }

    @Test func gzipCompressedTarArchivesAreRead() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/LICENSE", "license text")
        try tar.write(to: folder.path("plain.tar"))
        try gzip(folder.path("plain.tar"), to: folder.path("archive.tar.gz"))
        try ArchiveExtractor.extract(
            folder.path("archive.tar.gz"), to: folder.path("out"), policy: ExtractionPolicy(stripsRoot: true))
        #expect(contents(folder.path("out/LICENSE")) == Data("license text".utf8))
    }

    @Test func zipArchivesAreReadWithTheirExecuteBits() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var zip = ZipBuilder()
        zip.file("rustfs", "binary", mode: 0o100_755)
        zip.file("docs/LICENSE", "text")
        try zip.data.write(to: folder.path("archive.zip"))
        let report = try ArchiveExtractor.extract(
            folder.path("archive.zip"), to: folder.path("out"), policy: ExtractionPolicy())
        #expect(report.files.map(\.string) == ["docs/LICENSE", "rustfs"])
        #expect(permissions(folder.path("out/rustfs")) == 0o700)
        #expect(permissions(folder.path("out/docs/LICENSE")) == 0o600)
    }

    @Test func filesThatAreNotSupportedArchivesCannotBeRead() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try Data("just some text, not an archive".utf8).write(to: folder.path("text.tar"))
        #expect(throws: ArchiveFailure.unreadable) {
            try ArchiveExtractor.extract(folder.path("text.tar"), to: folder.path("out"), policy: ExtractionPolicy())
        }
        #expect(throws: ArchiveFailure.unreadable) {
            try ArchiveExtractor.extract(folder.path("missing.tar"), to: folder.path("out"), policy: ExtractionPolicy())
        }
    }

    @Test func truncatedArchiveDataIsReported() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/data", bytes: 4_000)
        try tar.data.prefix(1_536).write(to: folder.path("short.tar"))
        #expect(throws: JerdError.self) {
            try ArchiveExtractor.extract(
                folder.path("short.tar"), to: folder.path("out"), policy: ExtractionPolicy(stripsRoot: true))
        }
    }

    /// An Automake source tree lists `aclocal.m4` before `configure.ac`. Write times would make
    /// `configure.ac` look newer, so `make` would run `aclocal`. The archive times keep the order.
    @Test func extractedFilesAndLinkCopiesKeepTheModificationTimesOfTheArchive() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/aclocal.m4", "generated", modified: 1_700_000_200)
        tar.file("root/configure.ac", "source", modified: 1_700_000_100)
        tar.hardlink("root/configure.in", to: "root/configure.ac")
        _ = try extract(tar, in: folder)
        #expect(modificationTime(folder.path("out/aclocal.m4")) == 1_700_000_200)
        #expect(modificationTime(folder.path("out/configure.ac")) == 1_700_000_100)
        #expect(modificationTime(folder.path("out/configure.in")) == 1_700_000_100)
    }

    @Test func cancelledExtractionStopsBeforeWriting() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var tar = TarBuilder()
        tar.file("root/a", "a")
        let archive = folder.path("a.tar")
        try tar.write(to: archive)
        let output = folder.path("out")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ArchiveExtractor.extract(archive, to: output, policy: ExtractionPolicy(stripsRoot: true))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(FileProbe.presence(at: output.appendingPathComponent("a")) == .absent)
    }
}

/// The whole-second modification time of a file, as `make` compares it.
private func modificationTime(_ url: URL) -> Int {
    var info = stat()
    lstat(url.path, &info)
    return info.st_mtimespec.tv_sec
}

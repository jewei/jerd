import Foundation
import JerdFoundation
import JerdTestSupport
import JerdWeb
import Testing

@testable import JerdCLICore

@Suite struct CLIIniWriterTests {
    private static let expectedINI = """
        [PHP]
        date.timezone = UTC
        expose_php = Off
        log_errors = On
        memory_limit = -1
        max_execution_time = 0
        display_errors = stderr
        [opcache]
        opcache.enable_cli = 0

        """

    @Test func plainINIHasTheExactCLIPolicy() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url)
        let file = try CLIIniWriter(layout: layout).writeINI(caBundle: nil)
        #expect(file == layout.runtimes.cliINIFile)
        #expect(text(file) == Self.expectedINI)
        #expect(mode(file) == 0o600)
        #expect(mode(layout.runtimes.cliConfigurationDirectory) == 0o700)
    }

    @Test func localCAGoesToItsOwnFileWithQuotedPaths() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url)
        let writer = CLIIniWriter(layout: layout)
        let plain = try writer.writeINI(caBundle: nil)
        let before = contents(plain)
        let bundle = layout.runtimes.cliCABundleFile
        let file = try writer.writeINI(caBundle: bundle)
        #expect(file == layout.runtimes.cliLocalTLSINIFile)
        #expect(
            text(file)
                == Self.expectedINI
                + "\n[curl]\ncurl.cainfo = \"\(bundle.path)\"\n[openssl]\nopenssl.cafile = \"\(bundle.path)\"\n")
        #expect(contents(plain) == before)
    }

    @Test func unchangedFileIsNotRewritten() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let writer = CLIIniWriter(layout: DataLayout(root: directory.url))
        let file = try writer.writeINI(caBundle: nil)
        let first = inode(file)
        _ = try writer.writeINI(caBundle: nil)
        #expect(inode(file) == first)
    }

    @Test func changedFileIsReplaced() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url)
        try OwnedDirectory.create(layout.runtimes.cliConfigurationDirectory)
        try AtomicFile.write(Data("memory_limit = 1\n".utf8), to: layout.runtimes.cliINIFile)
        _ = try CLIIniWriter(layout: layout).writeINI(caBundle: nil)
        #expect(text(layout.runtimes.cliINIFile) == Self.expectedINI)
    }

    @Test func linkedINIIsPreservedAndRefused() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url)
        try OwnedDirectory.create(layout.runtimes.cliConfigurationDirectory)
        let target = try directory.file("elsewhere.ini", "user")
        try FileManager.default.createSymbolicLink(at: layout.runtimes.cliINIFile, withDestinationURL: target)
        #expect(throws: JerdError.self) { try CLIIniWriter(layout: layout).writeINI(caBundle: nil) }
        #expect(text(target) == "user")
    }

    @Test func bundlePathWithINIExpansionIsRefused() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let writer = CLIIniWriter(layout: DataLayout(root: directory.url))
        #expect(throws: JerdError.self) { try writer.writeINI(caBundle: URL(fileURLWithPath: "/x/${HOME}/ca.pem")) }
    }

    @Test func emptyScanFolderIsPrivate() throws {
        let directory = try TemporaryDirectory(" cli café")
        defer { directory.remove() }
        let layout = DataLayout(root: directory.url)
        let folder = try CLIIniWriter(layout: layout).prepareEmptyScanDirectory()
        #expect(folder == layout.runtimes.cliEmptyINIDirectory)
        #expect(mode(folder) == 0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}

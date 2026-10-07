import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

/// The app does not embed RustFS, but it embeds the XZ library that the RustFS preparation needs.
@Suite("Bundled XZ library and on-demand RustFS")
struct BundledSupportLibraryTests {
    private func bootstrap(_ folder: TemporaryFolder) -> BundledRuntimeBootstrap {
        BundledRuntimeBootstrap(
            resources: folder.path("bundle"), layout: DataLayout(root: folder.path("data")), architecture: .arm64)
    }

    /// A bundle with the RustFS pin on demand (no payload) and, optionally, the XZ folder.
    private func onDemandBundle(
        _ folder: TemporaryFolder, xz: ((inout BundleBuilder) throws -> Void)? = { try $0.addXZ() }
    ) throws {
        var builder = BundleBuilder(root: folder.path("bundle"))
        try builder.add(
            .rustfs, id: "rustfs-1.0.0-arm64", version: "1.0.0",
            files: [.init(path: "rustfs", text: "b", executable: true)], embedded: false)
        // The pin has no payload in the app: remove the folder that the builder wrote.
        try FileManager.default.removeItem(at: folder.path("bundle/storage"))
        try xz?(&builder)
        try builder.writeCatalog()
    }

    @Test("An app without the RustFS payload installs no storage runtime and creates no folder")
    func onDemandRustFSInstallsNothing() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try onDemandBundle(folder)
        #expect(try await bootstrap(folder).installStorage() == nil)
        #expect(FileProbe.presence(at: folder.path("data/storage-runtimes")) == .absent)
    }

    @Test("The separate XZ folder gives the verified library and its license")
    func separateXZFolderGivesTheLibrary() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try onDemandBundle(folder)
        let library = try #require(try await bootstrap(folder).bundledLZMA())
        #expect(library.library == folder.path("bundle/support/xz/liblzma.5.dylib"))
        #expect(library.license == folder.path("bundle/support/xz/XZ-LICENSE.txt"))
    }

    @Test("A changed library file is refused and kept as it is")
    func changedLibraryIsRefused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try onDemandBundle(folder)
        let file = folder.path("bundle/support/xz/liblzma.5.dylib")
        try Data("changed".utf8).write(to: file)
        await #expect(throws: JerdError.invalid("The xz support file liblzma.5.dylib changed.")) {
            try await bootstrap(folder).bundledLZMA()
        }
        #expect(try Data(contentsOf: file) == Data("changed".utf8))
    }

    @Test("An extra file, a missing license, or another XZ version is refused")
    func otherFoldersAreRefused() async throws {
        let cases: [(inout BundleBuilder) throws -> Void] = [
            { try $0.addXZ(files: ["liblzma.5.dylib": "lzma", "XZ-LICENSE.txt": "0BSD", "extra.dylib": "x"]) },
            { try $0.addXZ(files: ["liblzma.5.dylib": "lzma"]) },
        ]
        for setup in cases {
            let folder = try TemporaryFolder()
            defer { folder.remove() }
            try onDemandBundle(folder, xz: setup)
            await #expect(throws: JerdError.self) { try await bootstrap(folder).bundledLZMA() }
        }
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try onDemandBundle(folder)
        // The catalog now pins another XZ release than the receipt records.
        var other = BundleBuilder(root: folder.path("other"))
        try other.addXZ(version: "5.8.5")
        try FileManager.default.removeItem(at: folder.path("bundle/support/xz"))
        try FileManager.default.moveItem(at: folder.path("other/support/xz"), to: folder.path("bundle/support/xz"))
        await #expect(throws: JerdError.invalid("The bundled XZ library does not match its pin.")) {
            try await bootstrap(folder).bundledLZMA()
        }
    }

    @Test("A development app without the XZ folder and without RustFS has no library")
    func developmentAppHasNoLibrary() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try onDemandBundle(folder, xz: nil)
        #expect(try await bootstrap(folder).bundledLZMA() == nil)
    }
}

import Foundation
import JerdArchive
import JerdFoundation

/// The debug symbols of a release: copied from the archive, matched to the app binaries by UUID, and
/// zipped for the release assets. Validation checks the folder and also the zip that will be published.
struct SymbolArchive: Sendable {
    /// The zip holds a few dSYM bundles; this limit stops a damaged or hostile file early.
    static let extractionLimit: Int64 = 1_073_741_824

    let shell: ReleaseShell

    func create(layout: CandidateLayout, zip: URL) async throws {
        try await shell.run(
            SystemProgram.ditto, [layout.archive.appending(path: "dSYMs").path, layout.symbols.path],
            limit: TimeLimit.appCopy)
        try await verify(app: layout.app, symbols: layout.symbols)
        try await shell.run(
            SystemProgram.ditto, ["-c", "-k", "--keepParent", layout.symbols.path, zip.path], limit: TimeLimit.appCopy)
    }

    /// Each app binary has exactly the UUIDs of its dSYM.
    func verify(app: URL, symbols: URL) async throws {
        for pair in SymbolUUIDs.pairs {
            let binary = try await uuids(app.appending(path: pair.binary))
            let symbol = try await uuids(symbols.appending(path: pair.symbols))
            guard !binary.isEmpty, binary == symbol else {
                throw DevFailure.checkFailed("The debug symbols do not match \(pair.binary).")
            }
        }
    }

    /// Extracts the published zip with the safe extractor (paths stay inside, no links are created)
    /// and checks its symbols too.
    func verifyZip(_ zip: URL, app: URL) async throws {
        let folder = try FileTree.makeTemporaryFolder(prefix: "jerd-symbols")
        defer { try? FileManager.default.removeItem(at: folder) }
        let policy = ExtractionPolicy(outputLimit: Self.extractionLimit)
        do {
            _ = try await Task.detached {
                try ArchiveExtractor.extract(zip, to: folder.appending(path: "x"), policy: policy)
            }
            .value
        } catch {
            throw DevFailure.checkFailed(
                "The symbols zip cannot be extracted safely: \(PayloadInventory.message(of: error))")
        }
        try await verify(app: app, symbols: folder.appending(path: "x/symbols"))
    }

    private func uuids(_ file: URL) async throws -> Set<SymbolUUIDs.Entry> {
        let result = try await shell.xcrun(["dwarfdump", "--uuid", file.path], limit: TimeLimit.probe)
        return SymbolUUIDs.parse(result.standardOutput)
    }
}

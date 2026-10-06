import Darwin
import Foundation
import JerdFoundation
import JerdManifest

/// Verifies a payload folder that an older Jerd installed, before the app uses it (RT-6).
///
/// Older builds installed bundled payloads as `<group folder>/<installation ID>/` with one of three
/// receipt forms (`LegacyPayloadReceipt`). Service records that those builds wrote still name these
/// folders, so the app keeps using them. Each use is verified like a current payload (spec D B6,
/// DB6, ML5, ST4, made strict): a real folder that the user owns, a valid receipt of the group's
/// form, exactly the recorded files with their SHA-256 (only `.DS_Store` is ignored), and for the
/// database form every recorded executable with its execute bit. Nothing is ever changed.
public struct LegacyPayloadVerifier: Sendable {
    private let layout: RuntimeLayout

    public init(layout: DataLayout) { self.layout = layout.runtimes }

    /// Verifies `<group folder>/<id>/` off the cooperative pool.
    /// - Throws: `.invalid` for an unsafe ID, a folder that is not real or not owned, a receipt that
    ///   cannot be read, or any changed, extra, or missing file; `CancellationError`.
    public func verify(id: String, group: PayloadGroup) async throws -> LegacyInstalledPayload {
        guard PayloadIdentifier.isValid(id) else { throw JerdError.invalid("The runtime ID \(id) is invalid.") }
        let folder = layout.payloadDirectory(for: group).appendingPathComponent(id, isDirectory: true)
        let format = LegacyPayloadReceipt.Format(group: group)
        let receipt = try await BlockingWork.run { try Self.verify(folder, format: format) }
        return LegacyInstalledPayload(id: id, group: group, directory: folder, receipt: receipt)
    }

    /// The synchronous check of one folder.
    package static func verify(_ folder: URL, format: LegacyPayloadReceipt.Format) throws -> LegacyPayloadReceipt {
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else {
            throw JerdError.invalid("The runtime directory is invalid.")
        }
        let data = try AtomicFile.read(
            folder.appendingPathComponent(format.fileName), limit: LegacyPayloadReceipt.sizeLimit)
        let receipt = try LegacyPayloadReceipt.decode(data, format: format)
        let actual = try PayloadScanner.scan(folder, ignoring: [format.fileName], ignoresFinderMetadata: true)
        try PayloadComparison.requireHashes(receipt.fileHashes, actual: actual)
        for path in (receipt.executables ?? []).sorted() where actual[path]?.executable != true {
            throw JerdError.invalid("The installed runtime is not executable: \(path.string).")
        }
        return receipt
    }
}

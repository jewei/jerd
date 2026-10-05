import Darwin
import Foundation
import JerdFoundation
import JerdManifest

/// Installs one bundled payload into a private folder (rules B6/B8, DB5/DB6, ML4/ML5, ST3/ST4 in one place).
///
/// The target folder is `<directory>/<folder ID>`. An existing target is verified and used, never
/// replaced. Otherwise the bundle copy is verified (exact file set, hashes, executable flags), the
/// files are copied into a staging folder with modes 0700/0600, the receipt bytes are added, the
/// copy is verified again, and one rename publishes it. All file work runs off the cooperative pool.
public struct VerifiedPayloadInstaller: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func install(_ payload: BundledPayload) async throws -> InstalledPayload {
        let directory = directory
        return try await BlockingWork.run { try Self.install(payload, into: directory) }
    }

    private static func install(_ payload: BundledPayload, into directory: URL) throws -> InstalledPayload {
        let receipt = payload.receipt
        try OwnedDirectory.create(directory)
        let target = directory.appendingPathComponent(receipt.folderID, isDirectory: true)
        if FileProbe.presence(at: target).mayExist {
            try requireOwnedFolder(target)
            try verify(target, receipt: receipt)
            return InstalledPayload(receipt: receipt, directory: target)
        }
        do {
            try verify(payload.origin, receipt: receipt)
        } catch let error as JerdError where error.kind == .invalid {
            throw JerdError.invalid(
                "The bundled \(receipt.kind.title) runtime does not match its receipt. Install Jerd again.")
        }
        let staging = try StagingFolder(in: directory)
        defer { staging.remove() }
        for (path, record) in receipt.fileRecords.sorted(by: { $0.key < $1.key }) {
            try copy(path.url(in: payload.origin), to: path.url(in: staging.url), within: staging.url, record: record)
        }
        try AtomicFile.write(payload.receiptBytes, to: staging.url.appendingPathComponent(PayloadReceipt.fileName))
        try verify(staging.url, receipt: receipt)
        try FolderMove.withoutReplacing(staging.url, to: target)
        return InstalledPayload(receipt: receipt, directory: target)
    }

    /// The folder holds exactly the receipt files with their hashes and modes, plus the receipt.
    static func verify(_ folder: URL, receipt: PayloadReceipt) throws {
        let actual = try PayloadScanner.scan(folder, ignoring: [PayloadReceipt.fileName], ignoresFinderMetadata: true)
        try PayloadComparison.requireRecords(receipt.fileRecords, actual: actual)
    }

    private static func requireOwnedFolder(_ folder: URL) throws {
        var info = stat()
        guard lstat(folder.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else {
            throw JerdError.invalid("The runtime directory is invalid.")
        }
    }

    private static func copy(_ source: URL, to destination: URL, within root: URL, record: PayloadFileRecord) throws {
        try OwnedDirectory.create(destination.deletingLastPathComponent(), within: root)
        try FileManager.default.copyItem(at: source, to: destination)
        guard chmod(destination.path, record.executable ? 0o700 : 0o600) == 0 else {
            throw JerdError.unavailable("Cannot protect \(destination.path) (\(SystemError.describe(errno))).")
        }
    }
}

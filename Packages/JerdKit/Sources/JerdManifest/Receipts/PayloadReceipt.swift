import Foundation
import JerdFoundation

/// The one receipt schema of a bundled payload: `<payload folder>/payload-receipt.json`.
///
/// The build tool writes it beside the prepared files. The app copies it unchanged into the
/// installed folder. Every listed file has its SHA-256 and its executable flag. The receipt
/// itself is not listed.
public struct PayloadReceipt: Codable, Equatable, Sendable {
    /// The receipt file name inside a payload folder.
    public static let fileName = "payload-receipt.json"
    /// A receipt file must be at most this many bytes.
    public static let sizeLimit = 8_000_000
    /// The maximum number of recorded files.
    public static let fileLimit = 50_000
    /// The only schema version.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// The payload ID from the pin catalog, for example `php-8.5.11-arm64`.
    public let id: String
    public let kind: RuntimeKind
    /// The version that the runtime reports (the engine version for PostgreSQL).
    public let version: String
    /// The pinned catalog version.
    public let releaseVersion: String
    public let architecture: CPUArchitecture
    /// The pinned artifact digest (for the Laravel installer, the SHA-256 of `composer.lock`).
    public let archiveSHA256: String
    public let executable: RelativePath
    public let secondaryExecutable: RelativePath?
    public let files: [String: PayloadFileRecord]
    /// Set by the release tool after it signs the payload binaries.
    public let signing: PayloadSigning?

    public init(
        id: String, kind: RuntimeKind, version: String, releaseVersion: String, architecture: CPUArchitecture,
        archiveSHA256: String, executable: RelativePath, secondaryExecutable: RelativePath?,
        files: [RelativePath: PayloadFileRecord], signing: PayloadSigning? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.kind = kind
        self.version = version
        self.releaseVersion = releaseVersion
        self.architecture = architecture
        self.archiveSHA256 = archiveSHA256
        self.executable = executable
        self.secondaryExecutable = secondaryExecutable
        self.files = Dictionary(uniqueKeysWithValues: files.map { ($0.key.string, $0.value) })
        self.signing = signing
    }

    /// The recorded files as validated paths. Valid after `decode` or `init`.
    public var fileRecords: [RelativePath: PayloadFileRecord] {
        Dictionary(uniqueKeysWithValues: files.compactMap { key, value in RelativePath(key).map { ($0, value) } })
    }

    /// The folder name of this exact payload: see `PayloadFolderID`.
    public var folderID: String { PayloadFolderID.make(payloadID: id, files: fileRecords) }

    /// The same receipt with new file records, for example after the release tool signs binaries.
    public func replacingFiles(
        _ newFiles: [RelativePath: PayloadFileRecord], signing: PayloadSigning?
    ) -> PayloadReceipt {
        PayloadReceipt(
            id: id, kind: kind, version: version, releaseVersion: releaseVersion, architecture: architecture,
            archiveSHA256: archiveSHA256, executable: executable, secondaryExecutable: secondaryExecutable,
            files: newFiles, signing: signing)
    }

    /// The exact bytes to save: pretty, sorted keys, so that reviews and diffs are readable.
    public func encoded() throws -> Data {
        try validate()
        return try JSONFileFormat.settings.makeEncoder().encode(self)
    }

    /// Decodes and validates receipt bytes.
    /// - Throws: `.invalid` when the bytes are too large, do not decode, or break a rule.
    public static func decode(_ data: Data) throws -> PayloadReceipt {
        guard data.count <= sizeLimit else { throw invalid("The payload receipt is too large.") }
        let receipt: PayloadReceipt
        do {
            receipt = try JSONDecoder().decode(PayloadReceipt.self, from: data)
        } catch {
            throw invalid("The payload receipt cannot be read. \(FailureDetail.describe(error))")
        }
        try receipt.validate()
        return receipt
    }

    static func invalid(_ message: String) -> JerdError { .invalid(message) }
}

import Foundation
import JerdFoundation

/// A receipt that older builds wrote into installed bundled payload folders. Read only.
///
/// Three forms exist on users' disks:
/// - `runtimes/<id>/jerd-receipt.json`: `{schemaVersion, archiveSHA256, fileSHA256: {path: sha256}}` plus
///   informational keys (development group).
/// - `database-runtimes/<id>/jerd-receipt.json`: `{schemaVersion, archiveSHA256, files: {path: {sha256, executable}}}`.
/// - `mail-runtimes/<id>/receipt.json` and `storage-runtimes/<id>/receipt.json`:
///   `{schemaVersion, archiveSHA256, files: {path: sha256}}`.
public struct LegacyPayloadReceipt: Equatable, Sendable {
    /// The three legacy receipt forms.
    public enum Format: CaseIterable, Sendable {
        case development
        case database
        case service

        /// The receipt file name of this form.
        public var fileName: String { self == .service ? "receipt.json" : "jerd-receipt.json" }
    }

    /// A legacy receipt file must be at most this many bytes.
    public static let sizeLimit = 8_000_000
    /// The maximum number of recorded files (the old writers allowed up to 20 000).
    public static let fileLimit = 20_000

    public let format: Format
    public let archiveSHA256: String
    /// Every recorded file and its SHA-256.
    public let fileHashes: [RelativePath: String]
    /// The files recorded as executable. Only the database form records this; nil for the others.
    public let executables: Set<RelativePath>?

    /// Decodes and validates a legacy receipt of a known form.
    /// - Throws: `.invalid("The installed runtime receipt is invalid. Existing files were preserved.")`.
    public static func decode(_ data: Data, format: Format) throws -> LegacyPayloadReceipt {
        guard data.count <= sizeLimit else { throw invalid }
        do {
            switch format {
            case .development:
                let raw = try JSONDecoder().decode(DevelopmentForm.self, from: data)
                return try make(format, raw.schemaVersion, raw.archiveSHA256, raw.fileSHA256, executables: nil)
            case .database:
                let raw = try JSONDecoder().decode(DatabaseForm.self, from: data)
                let hashes = raw.files.mapValues(\.sha256)
                let executables = Set(raw.files.filter(\.value.executable).compactMap { RelativePath($0.key) })
                return try make(format, raw.schemaVersion, raw.archiveSHA256, hashes, executables: executables)
            case .service:
                let raw = try JSONDecoder().decode(ServiceForm.self, from: data)
                return try make(format, raw.schemaVersion, raw.archiveSHA256, raw.files, executables: nil)
            }
        } catch let error as JerdError {
            throw error
        } catch {
            throw invalid
        }
    }

    private static func make(
        _ format: Format, _ schemaVersion: Int, _ archiveSHA256: String, _ files: [String: String],
        executables: Set<RelativePath>?
    ) throws -> LegacyPayloadReceipt {
        var hashes: [RelativePath: String] = [:]
        for (key, value) in files {
            guard let path = RelativePath(key), FileDigest.isSHA256Hex(value) else { throw invalid }
            hashes[path] = value
        }
        guard schemaVersion == 1, FileDigest.isSHA256Hex(archiveSHA256), (1...fileLimit).contains(hashes.count) else {
            throw invalid
        }
        return LegacyPayloadReceipt(
            format: format, archiveSHA256: archiveSHA256, fileHashes: hashes, executables: executables)
    }

    static var invalid: JerdError {
        .invalid("The installed runtime receipt is invalid. Existing files were preserved.")
    }

    private struct DevelopmentForm: Decodable {
        let schemaVersion: Int
        let archiveSHA256: String
        let fileSHA256: [String: String]
    }

    private struct DatabaseForm: Decodable {
        let schemaVersion: Int
        let archiveSHA256: String
        let files: [String: PayloadFileRecord]
    }

    private struct ServiceForm: Decodable {
        let schemaVersion: Int
        let archiveSHA256: String
        let files: [String: String]
    }
}

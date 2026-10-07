import Foundation
import JerdFoundation

/// The receipt of a managed runtime build: `runtime-updates/<folder>/update-receipt.json`.
///
/// The keys, the value forms, and the encoder options are a compatibility contract with
/// installed copies: default `JSONEncoder` (compact, unsorted), `secondaryExecutable` omitted
/// when nil, and `files` maps a relative POSIX path to a lowercase SHA-256 without the receipt itself.
public struct BuildReceipt: Codable, Equatable, Sendable {
    /// The receipt file name inside a build folder.
    public static let fileName = "update-receipt.json"
    /// A receipt file must be smaller than this many bytes.
    public static let sizeLimit = 8_000_000
    /// The maximum number of recorded files.
    public static let fileLimit = 50_000
    /// The only schema version.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let kind: RuntimeKind
    /// The version that the runtime reports. For PostgreSQL this is the engine version, for example `18.6`.
    public let version: String
    /// The catalog version. For PostgreSQL this is the Postgres.app version, for example `2.9.6`.
    public let releaseVersion: String
    /// The verified artifact digest. For the Laravel installer it is the SHA-256 of `composer.lock`.
    public let archiveSHA256: String
    public let executable: String
    /// PHP-FPM for PHP, otherwise nil.
    public let secondaryExecutable: String?
    public let files: [String: String]

    public init(
        kind: RuntimeKind, version: String, releaseVersion: String, archiveSHA256: String,
        executable: RelativePath, secondaryExecutable: RelativePath?, files: [RelativePath: String]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.kind = kind
        self.version = version
        self.releaseVersion = releaseVersion
        self.archiveSHA256 = archiveSHA256
        self.executable = executable.string
        self.secondaryExecutable = secondaryExecutable?.string
        self.files = Dictionary(uniqueKeysWithValues: files.map { ($0.key.string, $0.value) })
    }

    /// Decodes and validates receipt bytes.
    /// - Throws: `.invalid` with the user message of an invalid receipt.
    public static func decode(_ data: Data) throws -> BuildReceipt {
        guard data.count < sizeLimit else { throw JerdError.invalid("The update receipt is too large.") }
        let receipt: BuildReceipt
        do {
            receipt = try JSONDecoder().decode(BuildReceipt.self, from: data)
        } catch {
            throw invalidReceipt
        }
        try receipt.validate()
        return receipt
    }

    /// The exact bytes to save: `JSONFileFormat.compact`.
    public func encoded() throws -> Data {
        try validate()
        return try JSONFileFormat.compact.makeEncoder().encode(self)
    }

    /// The recorded files as validated paths. Valid after `decode` or `init`.
    public var fileHashes: [RelativePath: String] {
        Dictionary(uniqueKeysWithValues: files.compactMap { key, value in RelativePath(key).map { ($0, value) } })
    }

    /// The executable path. Valid after `decode` or `init`.
    public var executablePath: RelativePath? { RelativePath(executable) }

    /// The secondary executable path, when one is recorded.
    public var secondaryExecutablePath: RelativePath? { secondaryExecutable.flatMap { RelativePath($0) } }

    static var invalidReceipt: JerdError {
        .invalid("The update receipt is invalid. Existing files were preserved.")
    }
}

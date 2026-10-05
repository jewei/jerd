import Foundation
import JerdManifest

/// An installed managed build in `runtime-updates/`. Builds are immutable and never replaced.
public struct ManagedRuntime: Identifiable, Hashable, Sendable {
    public let kind: RuntimeKind
    /// The version that the runtime reports. Only PostgreSQL differs from `releaseVersion` (engine vs Postgres.app).
    public let version: String
    /// The catalog version of the release.
    public let releaseVersion: String
    /// The verified archive digest (for the Laravel installer, the SHA-256 of `composer.lock`).
    public let archiveSHA256: String
    public let directory: URL
    public let executable: URL
    /// PHP-FPM for PHP, otherwise nil.
    public let secondaryExecutable: URL?

    public init(receipt: BuildReceipt, directory: URL) {
        kind = receipt.kind
        version = receipt.version
        releaseVersion = receipt.releaseVersion
        archiveSHA256 = receipt.archiveSHA256
        self.directory = directory
        executable = directory.appendingPathComponent(receipt.executable)
        secondaryExecutable = receipt.secondaryExecutable.map { directory.appendingPathComponent($0) }
    }

    public var id: String { "\(kind.rawValue)-\(releaseVersion)-\(archiveSHA256)" }

    /// The folder name, which other records use as the runtime ID.
    public var folderName: String { directory.lastPathComponent }

    /// True when this build installs `release`.
    ///
    /// A release with a digest must have exactly that digest. A release whose digest is known only
    /// after the download (MySQL, signed) or after resolution (Laravel) matches its kind and version,
    /// so its installed build is found and not downloaded again (fixes P-I3).
    public func matches(_ release: RuntimeRelease) -> Bool {
        guard kind == release.kind, releaseVersion == release.version else { return false }
        return release.archiveSHA256.map { $0 == archiveSHA256 } ?? true
    }
}

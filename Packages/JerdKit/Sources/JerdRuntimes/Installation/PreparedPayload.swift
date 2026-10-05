import Foundation
import JerdFoundation
import JerdManifest

/// A prepared, probed, and hashed runtime folder that is ready for its receipt.
public struct PreparedPayload: Sendable {
    /// The folder inside the staging folder.
    public let directory: URL
    public let release: RuntimeRelease
    /// The version that the runtime reports.
    public let version: String
    /// The verified archive digest, or the SHA-256 of `composer.lock` for the Laravel installer.
    public let archiveSHA256: String
    public let executable: RelativePath
    public let secondaryExecutable: RelativePath?
    public let files: [RelativePath: PayloadFileRecord]

    /// The update receipt of a managed build.
    public func buildReceipt() -> BuildReceipt {
        BuildReceipt(
            kind: release.kind, version: version, releaseVersion: release.version, archiveSHA256: archiveSHA256,
            executable: executable, secondaryExecutable: secondaryExecutable, files: files.mapValues(\.sha256))
    }

    /// The payload receipt of a bundled payload with the pin ID `id`.
    public func payloadReceipt(id: String) -> PayloadReceipt {
        PayloadReceipt(
            id: id, kind: release.kind, version: version, releaseVersion: release.version,
            architecture: release.architecture, archiveSHA256: archiveSHA256, executable: executable,
            secondaryExecutable: secondaryExecutable, files: files)
    }
}

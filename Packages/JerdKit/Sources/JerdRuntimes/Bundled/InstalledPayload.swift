import Foundation
import JerdManifest

/// A bundled payload installed in Application Support. Its folder name is its runtime ID.
public struct InstalledPayload: Hashable, Sendable {
    /// The folder name: see `PayloadFolderID`.
    public let id: String
    public let kind: RuntimeKind
    /// The version that the runtime reports (the engine version for PostgreSQL).
    public let version: String
    public let directory: URL
    public let executable: URL
    /// PHP-FPM for PHP, otherwise nil.
    public let secondaryExecutable: URL?

    public init(receipt: PayloadReceipt, directory: URL) {
        id = directory.lastPathComponent
        kind = receipt.kind
        version = receipt.version
        self.directory = directory
        executable = receipt.executable.url(in: directory)
        secondaryExecutable = receipt.secondaryExecutable?.url(in: directory)
    }
}

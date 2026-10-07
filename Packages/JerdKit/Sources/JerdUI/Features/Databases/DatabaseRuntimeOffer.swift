import Foundation
import JerdDatabases
import JerdRuntimes

/// A database engine that Jerd can download and install on demand, from the reviewed pin that
/// the app carries. JerdLive builds it from the pinned release.
public struct DatabaseRuntimeOffer: Hashable, Sendable {
    public let engine: DatabaseEngine
    /// The version that the engine reports, for example `8.4.11`, or `18.6` for PostgreSQL (not the
    /// Postgres.app release that carries it).
    public let versionLabel: String
    /// The exact download size in bytes.
    public let downloadSize: Int64
    /// The host that serves the download, for example `cdn.mysql.com`.
    public let source: String
    /// The approximate size of the installed engine, when the pin states it.
    public let installedSize: Int64?
    /// True when Jerd also checks the publisher signature (MySQL).
    public let isSigned: Bool

    public init(
        engine: DatabaseEngine, versionLabel: String, downloadSize: Int64, source: String, installedSize: Int64? = nil,
        isSigned: Bool = false
    ) {
        self.engine = engine
        self.versionLabel = versionLabel
        self.downloadSize = downloadSize
        self.source = source
        self.installedSize = installedSize
        self.isSigned = isSigned
    }

    /// The engine and its version, for example `MySQL 8.4.11` or `PostgreSQL 18.6`.
    public var title: String { "\(engine.title) \(versionLabel)" }

    /// The download size for the user, for example `168 MB` (`ByteText`).
    public var sizeText: String { ByteText.format(downloadSize) }

    /// The free disk space that the installation needs: the download and the installed copy.
    public var requiredSpace: Int64 { downloadSize + (installedSize ?? 0) }
}

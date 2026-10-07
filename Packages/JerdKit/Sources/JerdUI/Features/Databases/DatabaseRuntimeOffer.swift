import Foundation
import JerdDatabases

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

    public init(engine: DatabaseEngine, versionLabel: String, downloadSize: Int64, source: String) {
        self.engine = engine
        self.versionLabel = versionLabel
        self.downloadSize = downloadSize
        self.source = source
    }

    /// The engine and its version, for example `MySQL 8.4.11` or `PostgreSQL 18.6`.
    public var title: String { "\(engine.title) \(versionLabel)" }

    /// The download size for the user, for example `168 MB`, with a no-break space so the
    /// number and its unit stay on one line.
    public var sizeText: String {
        ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

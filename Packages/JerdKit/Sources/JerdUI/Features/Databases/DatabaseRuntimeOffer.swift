import Foundation
import JerdDatabases

/// A database engine that Jerd can download and install on demand, from the reviewed pin that
/// the app carries. JerdLive builds it from the pinned release.
public struct DatabaseRuntimeOffer: Hashable, Sendable {
    public let engine: DatabaseEngine
    /// The pinned release, for example `8.4.11`, or `Postgres.app 2.9.6` for PostgreSQL.
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

    /// The engine and its release, for example `MySQL 8.4.11` or `PostgreSQL (Postgres.app 2.9.6)`.
    public var title: String {
        engine == .postgresql ? "\(engine.title) (\(versionLabel))" : "\(engine.title) \(versionLabel)"
    }

    /// The download size for the user, for example `168 MB`, with a no-break space so the
    /// number and its unit stay on one line.
    public var sizeText: String {
        ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)
            .replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

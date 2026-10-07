import Foundation
import JerdRuntimes

/// The runtime of a service page (RustFS for Storage, Mailpit for Mail) that Jerd can download and
/// install on demand, from the reviewed pin that the app carries. JerdLive builds it from the
/// pinned release.
public struct ServiceRuntimeOffer: Hashable, Sendable {
    /// The runtime name, for example `RustFS` or `Mailpit`.
    public let name: String
    /// The version that the runtime reports, for example `1.0.0`.
    public let versionLabel: String
    /// The exact download size in bytes.
    public let downloadSize: Int64
    /// The host that serves the download, for example `github.com`.
    public let source: String
    /// The approximate size of the installed runtime, when the pin states it.
    public let installedSize: Int64?
    /// True when the install reuses a copy on this Mac (an earlier payload or build): no download.
    public let reusesInstalledCopy: Bool

    public init(
        name: String, versionLabel: String, downloadSize: Int64, source: String, installedSize: Int64? = nil,
        reusesInstalledCopy: Bool = false
    ) {
        self.name = name
        self.versionLabel = versionLabel
        self.downloadSize = downloadSize
        self.source = source
        self.installedSize = installedSize
        self.reusesInstalledCopy = reusesInstalledCopy
    }

    /// `RustFS 1.0.0`.
    public var title: String { "\(name) \(versionLabel)" }

    /// The download size for the user, for example `87 MB` (`ByteText`).
    public var sizeText: String { ByteText.format(downloadSize) }

    /// The free disk space that the installation needs: the download and the installed copy, or
    /// nothing when it reuses a copy on this Mac.
    public var requiredSpace: Int64 { reusesInstalledCopy ? 0 : downloadSize + (installedSize ?? 0) }

    /// The same offer when a copy on this Mac is reused: the install downloads nothing.
    public func reusing() -> ServiceRuntimeOffer {
        ServiceRuntimeOffer(
            name: name, versionLabel: versionLabel, downloadSize: downloadSize, source: source,
            installedSize: installedSize, reusesInstalledCopy: true)
    }
}

import JerdManifest
import JerdRuntimes

/// A managed build that Jerd uses now, for example the Caddy executable of the web
/// environment. The Runtimes page marks a release as installed when such a build matches it.
public struct InstalledBuild: Hashable, Sendable {
    public let kind: RuntimeKind
    /// The version that the runtime reports, for messages.
    public let version: String
    /// The catalog version of the release.
    public let releaseVersion: String
    /// The verified archive digest.
    public let archiveSHA256: String

    public init(kind: RuntimeKind, version: String, releaseVersion: String, archiveSHA256: String) {
        self.kind = kind
        self.version = version
        self.releaseVersion = releaseVersion
        self.archiveSHA256 = archiveSHA256
    }

    /// The same rule as `ManagedRuntime.matches`: kind and version must match, and a release
    /// that states a digest must state this digest.
    public func matches(_ release: RuntimeRelease) -> Bool {
        guard kind == release.kind, releaseVersion == release.version else { return false }
        return release.archiveSHA256.map { $0 == archiveSHA256 } ?? true
    }
}

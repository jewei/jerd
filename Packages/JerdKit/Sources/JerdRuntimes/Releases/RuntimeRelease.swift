import Foundation
import JerdManifest

/// One installable release of a runtime, from a publisher catalog or from a reviewed pin.
public struct RuntimeRelease: Identifiable, Hashable, Sendable {
    public let kind: RuntimeKind
    /// The publisher release version. For PostgreSQL it is the Postgres.app version.
    public let version: String
    public let artifact: ReleaseArtifact
    /// The SHA-256 that the publisher (or the pin) states for the archive.
    public let archiveSHA256: String?
    /// A detached OpenPGP signature of the archive, checked with a pinned publisher key (MySQL).
    public let signatureURL: URL?
    /// The release page that the user can open.
    public let releasePage: URL
    public let architecture: CPUArchitecture
    /// The lowest macOS major version that the package supports, when the publisher states one.
    public let minimumOSMajor: Int?

    public init(
        kind: RuntimeKind, version: String, artifact: ReleaseArtifact, archiveSHA256: String?,
        signatureURL: URL? = nil, releasePage: URL, architecture: CPUArchitecture = .current,
        minimumOSMajor: Int? = nil
    ) {
        self.kind = kind
        self.version = version
        self.artifact = artifact
        self.archiveSHA256 = archiveSHA256
        self.signatureURL = signatureURL
        self.releasePage = releasePage
        self.architecture = architecture
        self.minimumOSMajor = minimumOSMajor
    }

    /// Two builds of one version have different IDs when their digests differ.
    public var id: String { "\(kind.rawValue)-\(version)" + (archiveSHA256.map { "-\($0)" } ?? "") }

    /// The version text for the user. PostgreSQL shows the Postgres.app version until its engine is probed.
    public var versionLabel: String { kind == .postgresql ? "Postgres.app \(version)" : version }

    /// How Jerd verifies this release, for the user.
    public var verification: ReleaseVerification {
        if let archiveSHA256 { return .digest(archiveSHA256) }
        if signatureURL != nil { return .publisherSignature }
        return .composerLock
    }

    /// The parsed version. Valid after the release policy accepts the release.
    public var parsedVersion: RuntimeVersion? { RuntimeVersion(version) }
}

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
    /// The reviewed signature file of a pinned release: its size limit and SHA-256. Nil for
    /// catalog releases, whose signature is limited by `RuntimePipeline.signatureLimit` only.
    public let pinnedSignature: PinnedFile?
    /// The version that the installed runtime must report, when the pin states one (the PostgreSQL
    /// version of a Postgres.app release). Nil for catalog releases.
    public let engineVersion: String?
    /// The approximate installed size in bytes that the pin states, or nil.
    public let installedSize: Int64?

    public init(
        kind: RuntimeKind, version: String, artifact: ReleaseArtifact, archiveSHA256: String?,
        signatureURL: URL? = nil, releasePage: URL, architecture: CPUArchitecture = .current,
        minimumOSMajor: Int? = nil, pinnedSignature: PinnedFile? = nil, engineVersion: String? = nil,
        installedSize: Int64? = nil
    ) {
        self.engineVersion = engineVersion
        self.installedSize = installedSize
        self.pinnedSignature = pinnedSignature
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
    /// A pinned engine version wins, so a pinned PostgreSQL shows `18.6`.
    public var versionLabel: String {
        engineVersion ?? (kind == .postgresql ? "Postgres.app \(version)" : version)
    }

    /// The name of the download, for example `PHP 8.5.11`. PostgreSQL comes from a Postgres.app release,
    /// whose version is not the PostgreSQL version.
    /// A pinned engine version names the engine (`PostgreSQL 18.6`).
    public var title: String {
        if let engineVersion { return "\(kind.title) \(engineVersion)" }
        return kind == .postgresql ? "Postgres.app \(version)" : "\(kind.title) \(version)"
    }

    /// The exact download size in bytes, when the publisher or the pin states it.
    public var downloadSize: Int64? {
        if case .archive(_, .exact(let size)) = artifact { return size }
        return nil
    }

    /// The free disk space that an installation needs: the download and the installed copy exist
    /// at the same time. Nil when neither size is known.
    public var requiredSpace: Int64? {
        guard downloadSize != nil || installedSize != nil else { return nil }
        return (downloadSize ?? 0) + (installedSize ?? 0)
    }

    /// How Jerd verifies this release, for the user.
    public var verification: ReleaseVerification {
        if let archiveSHA256 { return .digest(archiveSHA256) }
        if signatureURL != nil { return .publisherSignature }
        return .composerLock
    }

    /// The parsed version. Valid after the release policy accepts the release.
    public var parsedVersion: RuntimeVersion? { RuntimeVersion(version) }
}

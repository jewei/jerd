import Foundation
import JerdFoundation

/// One reviewed upstream artifact that the build prepares into a bundled payload.
///
/// A pin names exactly one artifact by URL, size, and SHA-256. MySQL pins also name the publisher
/// signature. The Laravel installer pin names a committed `composer.lock` instead of an archive.
public struct RuntimePin: Codable, Equatable, Sendable {
    /// The payload ID, for example `php-8.5.11-arm64`. It is the prefix of the installed folder name.
    public let id: String
    public let kind: RuntimeKind
    /// The upstream release version (the Postgres.app version for PostgreSQL).
    public let version: String
    /// The upstream archive. Nil only for the Laravel installer.
    public let archive: PinnedArchive?
    /// The detached publisher signature of the archive (MySQL).
    public let signature: PinnedFile?
    /// The committed Composer project of the Laravel installer.
    public let composerProject: PinnedComposerProject?
    /// The release page that a reviewer used.
    public let releasePage: URL
    /// False when the app does not embed this payload and installs it on demand. Nil (older
    /// catalogs, and the default) means embedded. Earlier readers ignore the key.
    public let embedded: Bool?
    /// The version that the runtime reports, when it differs from `version`: the PostgreSQL
    /// version of a Postgres.app release, for example `18.6`. Users see it before the install,
    /// and the installed runtime must report it. Earlier readers ignore the key.
    public let engineVersion: String?
    /// The approximate size in bytes of the installed runtime, for the free-space check and the
    /// install dialog of an on-demand pin. Earlier readers ignore the key.
    public let installedSize: Int64?

    public init(
        id: String, kind: RuntimeKind, version: String, archive: PinnedArchive?, signature: PinnedFile? = nil,
        composerProject: PinnedComposerProject? = nil, releasePage: URL, embedded: Bool? = nil,
        engineVersion: String? = nil, installedSize: Int64? = nil
    ) {
        self.id = id
        self.kind = kind
        self.version = version
        self.archive = archive
        self.signature = signature
        self.composerProject = composerProject
        self.releasePage = releasePage
        self.embedded = embedded
        self.engineVersion = engineVersion
        self.installedSize = installedSize
    }

    /// The largest installed size that a pin can state (8 GB).
    public static let installedSizeLimit: Int64 = 8_000_000_000

    /// True when the build copies the payload into the app.
    public var isEmbedded: Bool { embedded ?? true }

    /// The version that the user sees: the engine version when the pin states one.
    public var displayVersion: String { engineVersion ?? version }

    /// The bootstrap group of this pin.
    public var group: PayloadGroup? { PayloadGroup(kind: kind) }

    /// The digest that the payload receipt records as `archiveSHA256`.
    public var artifactSHA256: String? { archive?.sha256 ?? composerProject?.lockSHA256 }

    /// Checks the structural rules of one pin.
    public func validate() throws {
        guard PayloadIdentifier.isValid(id), RuntimeVersion(version) != nil, group != nil,
            releasePage.scheme == "https", engineVersion.map({ RuntimeVersion($0) != nil }) ?? true,
            installedSize.map({ (1...Self.installedSizeLimit).contains($0) }) ?? true
        else { throw RuntimePinCatalog.invalid("The pin \(id) has an invalid identity.") }
        // The app has no Composer project folder, so only an archive can install on demand.
        guard isEmbedded || archive != nil else {
            throw RuntimePinCatalog.invalid("The pin \(id) cannot install on demand: it names no archive.")
        }
        if kind == .laravel {
            guard archive == nil, signature == nil, let project = composerProject else {
                throw RuntimePinCatalog.invalid("The pin \(id) must name only a Composer project.")
            }
            try project.validate()
        } else {
            guard let archive, composerProject == nil else {
                throw RuntimePinCatalog.invalid("The pin \(id) must name one archive.")
            }
            try archive.validate()
            try signature?.validate()
            guard (signature != nil) == (kind == .mysql) else {
                throw RuntimePinCatalog.invalid("Only the MySQL pin names a publisher signature.")
            }
        }
    }
}

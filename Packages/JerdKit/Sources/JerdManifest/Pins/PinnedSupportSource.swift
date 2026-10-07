import JerdFoundation

/// A source archive that the release tool builds a support library from, for example XZ for RustFS.
public struct PinnedSupportSource: Codable, Equatable, Sendable {
    public let version: String
    public let archive: PinnedArchive

    public init(version: String, archive: PinnedArchive) {
        self.version = version
        self.archive = archive
    }

    func validate() throws {
        guard RuntimeVersion(version) != nil else {
            throw RuntimePinCatalog.invalid("The support source \(archive.url.absoluteString) has an invalid version.")
        }
        try archive.validate()
    }
}

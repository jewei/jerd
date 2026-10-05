import JerdFoundation

/// A committed Composer project (`composer.json` and `composer.lock`) that Composer installs exactly.
public struct PinnedComposerProject: Codable, Equatable, Sendable {
    /// The project folder, relative to the folder of the pin catalog.
    public let directory: RelativePath
    /// The SHA-256 of the committed `composer.lock`.
    public let lockSHA256: String

    public init(directory: RelativePath, lockSHA256: String) {
        self.directory = directory
        self.lockSHA256 = lockSHA256
    }

    func validate() throws {
        guard FileDigest.isSHA256Hex(lockSHA256) else {
            throw RuntimePinCatalog.invalid("The Composer project pin \(directory) is invalid.")
        }
    }
}

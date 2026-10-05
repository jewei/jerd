import Foundation

/// What a release installs from.
public enum ReleaseArtifact: Hashable, Sendable {
    /// A file to download. The size is either the exact asset size or an upper limit.
    case archive(URL, size: ByteLimit)
    /// A Composer package that Composer resolves to its newest allowed versions (managed Laravel updates).
    case composerPackage(String)
    /// A committed Composer project that Composer installs exactly from its lock file (pinned Laravel).
    case lockedComposerProject(URL)

    /// The download URL, for an archive.
    public var downloadURL: URL? {
        if case .archive(let url, _) = self { return url }
        return nil
    }
}

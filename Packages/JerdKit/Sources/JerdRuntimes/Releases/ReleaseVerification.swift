/// The verification that protects a release, as the Runtimes page explains it.
public enum ReleaseVerification: Hashable, Sendable {
    /// The archive must have this SHA-256, which the publisher states before the download.
    case digest(String)
    /// The archive must carry a valid signature of the pinned publisher key. Its digest is known only after download.
    case publisherSignature
    /// Composer verifies every package with its lock file over HTTPS. Jerd has no independent check.
    case composerLock
}

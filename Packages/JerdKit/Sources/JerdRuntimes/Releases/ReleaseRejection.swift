import JerdFoundation

/// Why the release policy refuses a release.
public enum ReleaseRejection: Hashable, Sendable {
    /// R1/R2: the version, size, or digest is missing or malformed.
    case incomplete
    /// The release has no verification method that Jerd supports.
    case unverifiable
    /// R3: a URL breaks the host allowlist.
    case unsupportedURL
    /// R5: another architecture or a newer macOS.
    case incompatible

    /// The user-visible error.
    public var error: JerdError {
        switch self {
        case .incomplete: .invalid("The update metadata is incomplete or invalid.")
        case .unverifiable: .invalid("The runtime download has no verification method.")
        case .unsupportedURL: HostAllowlist.unsupported
        case .incompatible: .unavailable("This runtime package is not compatible with this Mac.")
        }
    }
}

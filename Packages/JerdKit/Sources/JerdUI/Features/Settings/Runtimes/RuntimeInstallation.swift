import JerdManifest
import JerdRuntimes

/// The one installation that runs.
public struct RuntimeInstallation: Equatable, Sendable {
    public let kind: RuntimeKind
    public var progress: RuntimeInstallProgress?
    /// True after the download finished, while the build is put into use. It cannot be
    /// cancelled then.
    public var isActivating: Bool

    public init(kind: RuntimeKind, progress: RuntimeInstallProgress? = nil, isActivating: Bool = false) {
        self.kind = kind
        self.progress = progress
        self.isActivating = isActivating
    }

    /// The user can cancel until activation starts.
    public var canCancel: Bool { !isActivating }
}

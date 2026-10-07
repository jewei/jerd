import JerdRuntimes

/// The one RustFS installation that the Storage page runs.
public struct StorageRuntimeInstallation: Equatable, Sendable {
    public let offer: StorageRuntimeOffer
    /// True when Start began it: storage starts after RustFS is installed.
    public let startsStorage: Bool
    public var progress: RuntimeInstallProgress?

    public init(offer: StorageRuntimeOffer, startsStorage: Bool, progress: RuntimeInstallProgress? = nil) {
        self.offer = offer
        self.startsStorage = startsStorage
        self.progress = progress
    }

    /// The current step, or the first step before the installer reports one.
    public var message: String {
        progress?.message ?? "Preparing to install \(offer.title)…"
    }
}

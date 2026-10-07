import JerdRuntimes

/// The one on-demand runtime installation that a service page (Storage, Mail) runs.
public struct ServiceRuntimeInstallation: Equatable, Sendable {
    public let offer: ServiceRuntimeOffer
    /// True when Start began it: the service starts after its runtime is installed.
    public let startsService: Bool
    public var progress: RuntimeInstallProgress?

    public init(offer: ServiceRuntimeOffer, startsService: Bool, progress: RuntimeInstallProgress? = nil) {
        self.offer = offer
        self.startsService = startsService
        self.progress = progress
    }

    /// The current step, or the first step before the installer reports one.
    public var message: String {
        progress?.message ?? "Preparing to install \(offer.title)…"
    }
}

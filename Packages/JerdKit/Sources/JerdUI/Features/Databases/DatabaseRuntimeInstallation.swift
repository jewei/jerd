import JerdDatabases
import JerdRuntimes

/// The one database runtime installation that runs.
public struct DatabaseRuntimeInstallation: Equatable, Sendable {
    public let offer: DatabaseRuntimeOffer
    /// True when Add Database started it: the sheet shows the progress, and the service is
    /// created after the runtime is installed.
    public let addsService: Bool
    public var progress: RuntimeInstallProgress?

    public init(offer: DatabaseRuntimeOffer, addsService: Bool, progress: RuntimeInstallProgress? = nil) {
        self.offer = offer
        self.addsService = addsService
        self.progress = progress
    }

    public var engine: DatabaseEngine { offer.engine }

    /// The current step, or the first step before the installer reports one.
    public var message: String {
        progress?.message ?? "Preparing to install \(offer.title)…"
    }
}

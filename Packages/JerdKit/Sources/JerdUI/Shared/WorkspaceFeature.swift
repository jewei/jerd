/// A service area of the main window: Sites, Databases, Storage, or Mail. `AppState` builds
/// one model per feature from its port. The shell uses this protocol for the dashboard card,
/// the menu bar, the operation banner, polling, launch, and the staged quit.
@MainActor
public protocol WorkspaceFeature: AnyObject {
    /// The section that shows the feature.
    var section: AppSection { get }
    /// The dashboard card.
    var summary: FeatureSummary { get }
    /// The entries of the feature in the menu bar menu.
    var menuItems: [MenuBarItem] { get }
    /// Global work for the operation banner, or nil.
    var bannerActivity: BannerActivity? { get }
    var pollingPolicy: PollingPolicy { get }
    /// The parts of the feature that the staged quit stops, in any order.
    var shutdownParticipants: [any ShutdownParticipant] { get }
    /// Loads saved state once at app launch, independent of any window.
    func launch() async
    /// Reads the current state of the services. The poller calls it.
    func refresh() async
}

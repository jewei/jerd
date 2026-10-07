/// A service area of the main window: Sites, Databases, Storage, or Mail. `AppState` builds
/// one model per feature from its port. The shell uses this protocol for the dashboard card,
/// the menu bar, the operation banner, the File › New command, polling, launch, and the staged
/// quit. The views of a section (page, sidebar, toolbar) are wired in the shell; see the README.
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
    /// The polling loops. The default is one loop at `pollingPolicy` that calls `refresh()`.
    /// A feature with two kinds of state, for example sites and tunnels, returns two.
    var pollingTasks: [PollingTask] { get }
    /// The File › New command (⌘N) while the section shows, for example "New Database…", or
    /// nil when the section adds nothing. It works also when the sidebar is hidden.
    var newItemAction: FeatureAction? { get }
    /// The parts of the feature that the staged quit stops, in any order. The quit calls them
    /// only after `launch()` finished.
    var shutdownParticipants: [any ShutdownParticipant] { get }
    /// Loads saved state once at app launch, independent of any window.
    func launch() async
    /// Reads the current state of the services. The poller calls it.
    func refresh() async
}

extension WorkspaceFeature {
    public var pollingTasks: [PollingTask] {
        [PollingTask(policy: pollingPolicy) { [weak self] in await self?.refresh() }]
    }

    public var newItemAction: FeatureAction? { nil }
}

import Foundation
import Observation

/// The root object of the app: navigation, the settings models, the service features, the
/// window-level copy confirmation and alert, and the app lifecycle. It is built from one
/// `AppDependencies` value and does nothing until `launch()`.
@MainActor
@Observable
public final class AppState {
    public var navigation = NavigationState()
    public let appearance: AppearanceModel
    public let runtimes: RuntimesModel
    public let advanced: AdvancedModel
    public let appUpdates: AppUpdatesModel
    public let clipboard: Clipboard
    public let sites: SitesModel
    public let shutdown = ShutdownCoordinator()
    /// The service features in section order: Sites, Databases, Storage, Mail.
    public let features: [any WorkspaceFeature]
    /// The one window alert: a cancelled quit or a failed system setup.
    public var alert: AppAlert?
    public let info: AppInfo
    /// True after `launch()` finished.
    public internal(set) var isLaunched = false
    public internal(set) var activity = AppActivity()

    @ObservationIgnored let windows: any WindowPresenting
    @ObservationIgnored let workspace: any WorkspaceOpening
    @ObservationIgnored var pollers: [ServicePoller] = []
    @ObservationIgnored var hasStartedLaunch = false

    /// - Parameter features: The service features. Each feature work package builds its model
    ///   from its own port in `AppDependencies` and adds it here; until then the fixtures pass
    ///   in-memory features.
    public init(dependencies: AppDependencies, features: [any WorkspaceFeature] = []) {
        info = dependencies.info
        appearance = AppearanceModel(
            defaults: AppearanceDefaults(dependencies.defaults), presence: dependencies.presence,
            images: dependencies.iconImages)
        runtimes = RuntimesModel(port: dependencies.runtimes)
        advanced = AdvancedModel(
            recovery: dependencies.recovery, executables: dependencies.executables,
            https: dependencies.httpsRecovery, panels: dependencies.filePanels, workspace: dependencies.workspace)
        appUpdates = AppUpdatesModel(updater: dependencies.updater)
        clipboard = Clipboard(pasteboard: dependencies.pasteboard)
        windows = dependencies.windows
        workspace = dependencies.workspace
        sites = Self.makeSites(dependencies, clipboard: clipboard)
        self.features = ([sites] + features.filter { $0.section != .sites }).sorted {
            $0.section.rawValue < $1.section.rawValue
        }
        pollers = self.features.map { feature in
            ServicePoller(policy: feature.pollingPolicy, sleeper: dependencies.sleeper) { [weak feature] in
                await feature?.refresh()
            }
        }
        connectSitesShell()
    }

    /// The feature that a section shows, if it is built.
    public func feature(for section: AppSection) -> (any WorkspaceFeature)? {
        features.first { $0.section == section }
    }

    /// Shows a destination in the main window and brings the window to the front.
    public func open(_ destination: Destination) {
        navigation.show(destination)
        windows.showMainWindow()
    }

    /// Brings the main window to the front without a navigation change.
    public func openMainWindow() {
        windows.showMainWindow()
    }

    /// Opens a web address or file, for links on the pages.
    public func openURL(_ url: URL) {
        workspace.open(url)
    }

    /// The global work for the operation banner: the staged quit first, then feature work.
    public var bannerActivity: BannerActivity? {
        if let message = shutdown.message {
            return BannerActivity(message: message)
        }
        return features.lazy.compactMap(\.bannerActivity).first
    }
}

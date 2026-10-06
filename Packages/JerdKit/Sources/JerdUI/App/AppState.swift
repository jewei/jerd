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
    /// The registered PHP runtimes and the default PHP: one store for every page.
    public let registrations: RegistrationStore
    public let runtimes: RuntimesModel
    public let advanced: AdvancedModel
    public let appUpdates: AppUpdatesModel
    public let clipboard: Clipboard
    public let sites: SitesModel
    public let databases: DatabasesModel
    public let storage: StorageModel
    public let mail: MailModel
    public let commandLineTools: CommandLineToolsModel
    public let shutdown = ShutdownCoordinator()
    /// The one lock for system and configuration work. Sites, Runtimes, Advanced, and the
    /// command-line tools share it; the staged quit closes it first and waits for its work.
    public let operationLock = OperationLock()
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
    /// The launch, kept so a quit can wait for it.
    @ObservationIgnored var launchTask: Task<Void, Never>?
    /// The sections whose feature finished `launch()`.
    @ObservationIgnored var launchedSections: Set<AppSection> = []

    /// - Parameter features: The service features. Each feature work package builds its model
    ///   from its own port in `AppDependencies` and adds it here; until then the fixtures pass
    ///   in-memory features.
    public init(dependencies: AppDependencies, features: [any WorkspaceFeature] = []) {
        info = dependencies.info
        appearance = AppearanceModel(
            defaults: AppearanceDefaults(dependencies.defaults), presence: dependencies.presence,
            images: dependencies.iconImages)
        registrations = RegistrationStore(port: dependencies.executables)
        runtimes = RuntimesModel(port: dependencies.runtimes, registry: registrations, lock: operationLock)
        advanced = AdvancedModel(
            recovery: dependencies.recovery, executables: dependencies.executables,
            https: dependencies.httpsRecovery, panels: dependencies.filePanels, workspace: dependencies.workspace,
            registry: registrations, lock: operationLock)
        appUpdates = AppUpdatesModel(updater: dependencies.updater)
        clipboard = Clipboard(pasteboard: dependencies.pasteboard)
        windows = dependencies.windows
        workspace = dependencies.workspace
        let services = dependencies.services
        databases = DatabasesModel(port: services.databases, clipboard: clipboard, workspace: workspace)
        storage = StorageModel(port: services.storage, clipboard: clipboard, workspace: workspace)
        mail = MailModel(port: services.mail, clipboard: clipboard, workspace: workspace)
        commandLineTools = CommandLineToolsModel(port: services.commandLineTools, lock: operationLock)
        sites = Self.makeSites(dependencies, clipboard: clipboard, lock: operationLock)
        let builtFeatures: [any WorkspaceFeature] = [sites, databases, storage, mail]
        let built = Set(builtFeatures.map(\.section))
        self.features = (features.filter { !built.contains($0.section) } + builtFeatures).sorted {
            $0.section.rawValue < $1.section.rawValue
        }
        connectServiceNavigation()
        pollers = self.features.flatMap(\.pollingTasks).map { task in
            ServicePoller(policy: task.policy, sleeper: dependencies.sleeper, refresh: task.refresh)
        }
        connectSitesShell()
    }

    /// The feature that a section shows, if it is built.
    public func feature(for section: AppSection) -> (any WorkspaceFeature)? {
        features.first { $0.section == section }
    }

    /// The File › New command of the current section, if it has one.
    public var newItemAction: FeatureAction? {
        feature(for: navigation.section)?.newItemAction
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

    /// True from the first quit request until the quit is cancelled. Feature actions are off then.
    public var isQuitting: Bool { shutdown.isQuitting }

    /// The global work for the operation banner: the staged quit first, then feature work.
    public var bannerActivity: BannerActivity? {
        if let message = shutdown.message {
            return BannerActivity(message: message)
        }
        return features.lazy.compactMap(\.bannerActivity).first
    }
}

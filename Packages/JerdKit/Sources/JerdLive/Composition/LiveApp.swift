import AppKit
import JerdCLICore
import JerdUI

/// The live app: every UI port on the real domain and AppKit, and the launch that runs before
/// the features load. The app delegate owns one; the scenes read its `state`.
@MainActor
public final class LiveApp {
    public let state: AppState
    public let windows: MainWindowPresenter
    public let iconImages: AppIconImages
    let preparation: LaunchPreparation
    let activity: AppActivityMonitor
    let quitEvents: QuitAppleEventHandler

    /// Builds every port and the root state. Nothing runs and nothing changes on disk until
    /// `launch()`.
    /// - Parameters:
    ///   - defaults: The `dev.jerd.app` defaults domain.
    ///   - notifications: The center where AppKit reports the app and window activity.
    ///   - quit: The quit that the quit Apple Event runs; tests pass a recorder.
    public init(
        configuration: LiveConfiguration, updater: any AppUpdating, bundle: Bundle = .main,
        defaults: UserDefaults = .standard, notifications: NotificationCenter = .default,
        quit: @escaping @MainActor () -> Void = { ApplicationQuit.request() }
    ) {
        let domain = LiveDomain(configuration: configuration)
        let images = AppIconImages(bundle: bundle)
        let windows = MainWindowPresenter()
        let runtimes = LiveRuntimeInventory(domain: domain)
        let commandLineTools = LiveCommandLineTools(installer: .live(appBundle: configuration.appBundle))
        let dependencies = AppDependencies(
            info: AppInfo(bundle: bundle), defaults: defaults, presence: AppPresence(images: images),
            iconImages: images, updater: updater, runtimes: runtimes, recovery: LiveRecoveryPort(layout: domain.layout),
            executables: LiveExecutableRegistrations(domain: domain),
            httpsRecovery: LiveHTTPSRecovery(helper: domain.helper), windows: windows, pasteboard: SystemPasteboard(),
            workspace: SystemWorkspace(), filePanels: SheetFilePanels(), sleeper: TaskSleeper(),
            services: Self.servicePorts(domain, commandLineTools: commandLineTools),
            sites: LiveSitesPort(domain: domain),
            tunnels: LiveTunnelsPort(supervisor: domain.tunnels))
        state = AppState(dependencies: dependencies)
        activity = AppActivityMonitor(state: state, center: notifications)
        activity.start(isAppActive: NSApplication.shared.isActive)
        quitEvents = QuitAppleEventHandler(manager: .shared(), request: quit)
        self.windows = windows
        iconImages = images
        preparation = LaunchPreparation(
            staging: [domain.bootstrap, runtimes],
            launcher: configuration.refreshesCommandLineLauncher ? commandLineTools : nil)
    }

    /// Routes the quit Apple Event (Dock Quit, logout, restart, shutdown) through the quit that
    /// ends the sheets first. Call it in `applicationWillFinishLaunching`: AppKit installs its
    /// own handler before that call.
    public func installQuitEventHandler() {
        quitEvents.install()
    }

    /// Starts Jerd independent of any window: removes abandoned staging folders and refreshes an
    /// outdated command-line launcher, then launches every feature. Each feature's load installs
    /// its bundled runtimes before it reads its services.
    public func launch() async {
        await preparation.run()
        await state.launch()
    }

    private static func servicePorts(_ domain: LiveDomain, commandLineTools: any CommandLineToolsPort) -> ServicePorts {
        ServicePorts(
            databases: LiveDatabasesPort(domain: domain), storage: LiveStoragePort(domain: domain),
            mail: LiveMailPort(domain: domain), commandLineTools: commandLineTools)
    }
}

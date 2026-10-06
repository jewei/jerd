import AppKit
import JerdLive

/// Starts Jerd at launch, independent of any window, and answers reopen and quit requests.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updater: SparkleUpdater
    let live: LiveApp

    override init() {
        let updater = SparkleUpdater(bundle: .main)
        self.updater = updater
        live = LiveApp(configuration: Self.configuration(), updater: updater)
        super.init()
        let state = live.state
        updater.allowsUpdateChecks = { [weak state] in state?.appUpdates.allowsUpdateChecks ?? false }
    }

    /// Applies the Dock choice before any window shows, so a hidden Dock icon never flashes.
    func applicationWillFinishLaunching(_ notification: Notification) {
        live.state.appearance.apply()
    }

    /// Loads every service, starts the updater, and starts polling, also when no window opens.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let live = live
        Task { await live.launch() }
    }

    /// Closing the window keeps Jerd and its services running.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Opening Jerd again shows the window. This is the way back when the menu bar item and the
    /// Dock icon are both off.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        live.state.reopen()
        return true
    }

    /// Runs the staged quit. Every request gets exactly one reply.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        live.state.requestTermination { stopped in
            sender.reply(toApplicationShouldTerminate: stopped)
        }
        .applicationReply
    }

    /// The data root and launch options. A Debug build reads `JERD_DEBUG_DATA_ROOT`, so a test
    /// run can use an empty folder instead of the user's data, and `JERD_DEBUG_KEEP_LAUNCHER=1`,
    /// so a test run on the user's data keeps the user's command-line launcher. Release builds
    /// always use the user's data root.
    private static func configuration() -> LiveConfiguration {
        var configuration = LiveConfiguration(bundle: .main)
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let root = environment["JERD_DEBUG_DATA_ROOT"], root.hasPrefix("/") {
            configuration = LiveConfiguration(bundle: .main, dataRoot: URL(fileURLWithPath: root, isDirectory: true))
        }
        if environment["JERD_DEBUG_KEEP_LAUNCHER"] == "1" {
            configuration.refreshesCommandLineLauncher = false
        }
        #endif
        return configuration
    }
}

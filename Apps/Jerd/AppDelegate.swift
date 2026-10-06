import AppKit
import JerdLive
import os

/// Starts Jerd at launch, independent of any window, and answers reopen and quit requests.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let log = Logger(subsystem: "dev.jerd.app", category: "lifecycle")
    let updater: SparkleUpdater
    let live: LiveApp
    /// Set only for a Debug run on another data root: it puts back the user's window and menu
    /// bar state, which AppKit and SwiftUI write to the shared app domain, when Jerd quits.
    private let preferences: PreferenceGuard?

    override init() {
        let updater = SparkleUpdater(bundle: .main)
        self.updater = updater
        let configuration = Self.configuration()
        // Before any scene exists, so the copy has the user's values.
        preferences = PreferenceGuard.forRun(configuration)
        live = LiveApp(configuration: configuration, updater: updater, defaults: configuration.makeDefaults())
        super.init()
        let state = live.state
        updater.allowsUpdateChecks = { [weak state] in state?.appUpdates.allowsUpdateChecks ?? false }
    }

    /// Applies the Dock choice before any window shows, so a hidden Dock icon never flashes.
    /// Replaces AppKit's quit event handler, which AppKit installs before this call.
    func applicationWillFinishLaunching(_ notification: Notification) {
        live.state.appearance.apply()
        live.installQuitEventHandler()
    }

    /// Loads every service, starts the updater, and starts polling, also when no window opens.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let live = live
        Task { await live.launch() }
    }

    /// The staged quit has ended: the last call before the process exits.
    func applicationWillTerminate(_ notification: Notification) {
        preferences?.restore()
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
        let reply = live.state.requestTermination { stopped in
            Self.log.notice("The staged quit ended. Terminate: \(stopped, privacy: .public).")
            sender.reply(toApplicationShouldTerminate: stopped)
        }
        Self.log.notice("Quit requested. Reply: \(String(describing: reply), privacy: .public).")
        return reply.applicationReply
    }

    /// The data root and launch options. A Debug build reads `JERD_DEBUG_DATA_ROOT`, so a test
    /// run can use an empty folder instead of the user's data, with its own defaults domain
    /// (`LiveConfiguration.defaultsSuiteName`), and `JERD_DEBUG_KEEP_LAUNCHER=1`,
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

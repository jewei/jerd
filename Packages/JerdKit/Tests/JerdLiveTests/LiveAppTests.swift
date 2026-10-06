import AppKit
import Foundation
import JerdFoundation
import JerdUI
import Testing

@testable import JerdLive

@Suite("Live app composition")
@MainActor
struct LiveAppTests {
    final class SilentUpdater: AppUpdating {
        func start(events: @escaping @MainActor (AppUpdateEvent) -> Void) throws -> AppUpdaterState {
            AppUpdaterState(canCheck: false, automaticallyChecks: false, lastCheck: nil)
        }
        func checkForUpdates() {}
        func setAutomaticChecks(_ isEnabled: Bool) -> Bool { false }
    }

    static func configuration(in temporary: TemporaryDirectory) throws -> LiveConfiguration {
        let root = temporary.path(UUID().uuidString)
        let app = root.appendingPathComponent("Jerd.app", isDirectory: true)
        return LiveConfiguration(
            layout: DataLayout(root: root.appendingPathComponent("Jerd", isDirectory: true)), appBundle: app,
            resources: app.appendingPathComponent("Contents/Resources"),
            appVersion: "0.1.0")
    }

    /// A defaults domain that the test only reads, so no preferences file is written.
    static func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "dev.jerd.live-tests.\(UUID().uuidString)"))
    }

    @Test func buildingTheAppWiresEveryFeatureAndChangesNothingOnDisk() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let configuration = try Self.configuration(in: temporary)

        let live = LiveApp(
            configuration: configuration, updater: SilentUpdater(), bundle: .main, defaults: try Self.defaults())

        #expect(live.state.features.map(\.section) == [.sites, .databases, .storage, .mail])
        #expect(!live.state.isLaunched)
        #expect(!FileManager.default.fileExists(atPath: configuration.layout.root.path))
    }

    @Test func aSeparateDataRootNeverRefreshesTheUsersLauncher() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let live = LiveApp(
            configuration: try Self.configuration(in: temporary), updater: SilentUpdater(), bundle: .main,
            defaults: try Self.defaults())

        #expect(live.preparation.launcher == nil)
        #expect(live.preparation.staging.count == 2)
    }

    /// Spec F 2.9: the pollers use the visible rates only while the app is active. The app
    /// object posts the activity notifications; the live app must follow them.
    @Test func theLiveAppFollowsTheActivityThatAppKitReports() throws {
        let center = NotificationCenter()
        let live = LiveApp(
            configuration: try Self.configuration(), updater: SilentUpdater(), bundle: .main,
            defaults: try Self.defaults(), notifications: center)
        live.state.setWindowVisible(true)

        center.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        #expect(live.state.activity.isActive)
        #expect(live.state.activity.showsLiveState)

        center.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        #expect(!live.state.activity.isActive)
        #expect(!live.state.activity.showsLiveState)
    }

    /// A minimized or covered main window shows no live state, so polling slows down.
    @Test func aHiddenMainWindowSlowsThePollingOfTheLiveApp() throws {
        let center = NotificationCenter()
        let live = LiveApp(
            configuration: try Self.configuration(), updater: SilentUpdater(), bundle: .main,
            defaults: try Self.defaults(), notifications: center)
        live.state.setAppActive(true)
        live.state.setWindowVisible(true)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered,
            defer: true)
        window.identifier = NSUserInterfaceItemIdentifier(MainWindowPresenter.windowID)

        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)

        #expect(!live.state.activity.isWindowVisible)
        #expect(!live.state.activity.showsLiveState)
    }

    @Test func onlyTheMainWindowReportsTheWindowVisibility() {
        let name = NSWindow.didChangeOcclusionStateNotification

        #expect(
            AppActivityMonitor.change(for: name, windowIdentifier: "main", isWindowVisible: true)
                == .windowVisible(true))
        #expect(
            AppActivityMonitor.change(for: name, windowIdentifier: "main-1", isWindowVisible: false)
                == .windowVisible(false))
        #expect(AppActivityMonitor.change(for: name, windowIdentifier: nil, isWindowVisible: false) == nil)
        #expect(AppActivityMonitor.change(for: name, windowIdentifier: "sheet", isWindowVisible: false) == nil)
        #expect(
            AppActivityMonitor.change(
                for: NSWindow.didResizeNotification, windowIdentifier: "main", isWindowVisible: true)
                == nil)
    }

    /// The Dock Quit and logout send the quit Apple Event. The live app must route it to the
    /// quit that ends the sheets, because AppKit's own handler is dropped while a sheet shows.
    @Test func theLiveAppRoutesTheQuitAppleEventToTheQuitThatEndsTheSheets() throws {
        var quits = 0
        let live = LiveApp(
            configuration: try Self.configuration(), updater: SilentUpdater(), bundle: .main,
            defaults: try Self.defaults(), notifications: NotificationCenter()
        ) { quits += 1 }

        live.installQuitEventHandler()
        defer { live.quitEvents.remove() }
        let result = QuitAppleEventTests.dispatchQuitEvent()

        #expect(result == noErr)
        #expect(quits == 1)
    }
}

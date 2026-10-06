import AppKit
import JerdLive
import JerdUI
import Sparkle

/// The app updater on Sparkle's standard controller. The feed and key come from the signed
/// Info.plist and must be the official ones; automatic checks start off, and automatic
/// installation is off for good. During a quit every check is refused.
@MainActor
final class SparkleUpdater: NSObject, AppUpdating {
    /// False while the staged quit runs. The app delegate connects it to `AppUpdatesModel`.
    var allowsUpdateChecks: @MainActor () -> Bool = { false }

    private let bundle: Bundle
    private var controller: SPUStandardUpdaterController?
    private var feedURL: String?
    private var events: (@MainActor (AppUpdateEvent) -> Void)?
    private var observations: [NSKeyValueObservation] = []

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    func start(events: @escaping @MainActor (AppUpdateEvent) -> Void) throws -> AppUpdaterState {
        let feed = try UpdateCycleMapping.feedURL(in: bundle)
        feedURL = feed
        self.events = events
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        try updater.start()
        // Removes a feed that an earlier test build saved; the delegate supplies the feed anyway.
        _ = updater.clearFeedURLFromUserDefaults()
        observe(updater)
        return AppUpdaterState(
            canCheck: updater.canCheckForUpdates, automaticallyChecks: updater.automaticallyChecksForUpdates,
            lastCheck: updater.lastUpdateCheckDate)
    }

    func checkForUpdates() {
        guard let controller, allowsUpdateChecks() else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ isEnabled: Bool) -> Bool {
        guard let updater = controller?.updater else { return false }
        updater.automaticallyChecksForUpdates = isEnabled
        return updater.automaticallyChecksForUpdates
    }

    /// KVO can call from any thread; the values are read on the main actor, where Sparkle owns them.
    private func observe(_ updater: SPUUpdater) {
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
                Task { @MainActor in self?.events?(.canCheckChanged(updater.canCheckForUpdates)) }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] updater, _ in
                Task { @MainActor in self?.events?(.automaticChecksChanged(updater.automaticallyChecksForUpdates)) }
            },
        ]
    }

    fileprivate func send(_ event: AppUpdateEvent) {
        events?(event)
    }

    fileprivate var validatedFeedURL: String? { feedURL }
}

extension SparkleUpdater: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { validatedFeedURL }
    }

    /// Sparkle asks before every check, also a scheduled one.
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try MainActor.assumeIsolated {
            guard allowsUpdateChecks() else { throw UpdateCycleMapping.stoppingError() }
            send(.checkStarted)
        }
    }

    /// Sparkle terminates the app right after this call; AppKit would drop that request while a
    /// sheet shows, so "Install and Relaunch" ends the sheets first.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { ApplicationQuit.endOpenSheets() }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { send(.updateFound(version)) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { send(.noUpdateFound) }
    }

    nonisolated func updater(
        _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?
    ) {
        let result = UpdateCycleMapping.result(for: error)
        MainActor.assumeIsolated {
            send(.cycleFinished(lastCheck: updater.lastUpdateCheckDate, result: result))
        }
    }
}

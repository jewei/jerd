import AppKit
import Observation
import Sparkle
import JerdCore

@MainActor @Observable
final class AppUpdatesModel: NSObject, SPUUpdaterDelegate {
    private(set) var isStarted = false
    private(set) var automaticallyChecks = false
    private(set) var lastCheck: Date?
    private(set) var message = "Check for a new version of Jerd."
    private(set) var errorMessage: String?
    var isTerminating = false
    private var canCheck = false
    @ObservationIgnored private let configuration: AppUpdateConfiguration?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    var canCheckForUpdates: Bool { isStarted && canCheck && !isTerminating }
    var canChangePreferences: Bool { isStarted && !isTerminating }

    override init() {
        do {
            configuration = try AppUpdateConfiguration(
                feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        } catch {
            configuration = nil
            errorMessage = error.localizedDescription
        }
        super.init()
    }

    func start() {
        guard !isStarted, configuration != nil, !isTerminating else { return }
        let controller = self.controller ?? SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            // The signed bundle owns the feed URL. Remove old testing overrides.
            controller.updater.clearFeedURLFromUserDefaults()
            isStarted = true
            errorMessage = nil
            let updater = controller.updater
            canCheck = updater.canCheckForUpdates
            automaticallyChecks = updater.automaticallyChecksForUpdates
            lastCheck = updater.lastUpdateCheckDate
            observations = [
                updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor [weak self] in self?.canCheck = value }
                },
                updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, change in
                    let value = change.newValue ?? false
                    Task { @MainActor [weak self] in self?.automaticallyChecks = value }
                }
            ]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, let updater = controller?.updater else { return }
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard canChangePreferences, let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecks = updater.automaticallyChecksForUpdates
    }

    func feedURLString(for updater: SPUUpdater) -> String? { configuration?.feedURL.absoluteString }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !isTerminating else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "Jerd is stopping its services."])
        }
        errorMessage = nil
        message = "Checking for app updates…"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        message = "Jerd \(item.displayVersionString) is available."
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        message = "No new app update is available for this Mac."
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        lastCheck = updater.lastUpdateCheckDate
        guard let error = error as NSError? else { return }
        if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
            message = "No new app update is available for this Mac."
        } else if (error.domain == SUSparkleErrorDomain && error.code == SUError.installationCanceledError.rawValue)
                    || (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError) {
            message = "App update cancelled."
        } else {
            message = "The app update check did not finish."
            errorMessage = error.localizedDescription
        }
    }
}

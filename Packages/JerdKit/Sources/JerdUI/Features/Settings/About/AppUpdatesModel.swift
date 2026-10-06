import Foundation
import Observation

/// Jerd's own updates: the status line, the automatic check switch, and the last check.
/// While Jerd quits, no check starts and the preference cannot change.
@MainActor
@Observable
public final class AppUpdatesModel {
    /// The error that the Sparkle adapter throws from `mayPerform` during a quit.
    public static let stoppingMessage = "Jerd is stopping its services."

    public private(set) var isStarted = false
    public private(set) var automaticallyChecks = false
    public private(set) var lastCheck: Date?
    public private(set) var message = "Check for a new version of Jerd."
    public private(set) var errorMessage: String?
    /// True while the staged quit runs.
    public var isTerminating = false
    private var canCheck = false
    @ObservationIgnored private let updater: any AppUpdating

    public init(updater: any AppUpdating) {
        self.updater = updater
    }

    public var canCheckForUpdates: Bool { isStarted && canCheck && !isTerminating }
    public var canChangePreferences: Bool { isStarted && !isTerminating }
    /// The Sparkle adapter refuses a check while this is false.
    public var allowsUpdateChecks: Bool { !isTerminating }

    /// Starts the updater once. A configuration error shows on About; the updater stays off.
    public func start() {
        guard !isStarted, !isTerminating else { return }
        do {
            let state = try updater.start { [weak self] event in self?.handle(event) }
            isStarted = true
            errorMessage = nil
            canCheck = state.canCheck
            automaticallyChecks = state.automaticallyChecks
            lastCheck = state.lastCheck
        } catch {
            errorMessage = ErrorText.message(for: error)
        }
    }

    public func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updater.checkForUpdates()
    }

    public func setAutomaticChecks(_ isEnabled: Bool) {
        guard canChangePreferences else { return }
        automaticallyChecks = updater.setAutomaticChecks(isEnabled)
    }

    /// Applies one updater event to the status line.
    public func handle(_ event: AppUpdateEvent) {
        switch event {
        case .canCheckChanged(let value): canCheck = value
        case .automaticChecksChanged(let value): automaticallyChecks = value
        case .checkStarted:
            errorMessage = nil
            message = "Checking for app updates…"
        case .updateFound(let version): message = "Jerd \(version) is available."
        case .noUpdateFound: message = "No new app update is available for this Mac."
        case .cycleFinished(let date, let result): finish(lastCheck: date, result: result)
        }
    }

    private func finish(lastCheck date: Date?, result: AppUpdateCycleResult) {
        lastCheck = date
        switch result {
        case .completed: break
        case .noUpdate: message = "No new app update is available for this Mac."
        case .cancelled: message = "App update cancelled."
        case .failed(let description):
            message = "The app update check did not finish."
            errorMessage = description
        }
    }
}

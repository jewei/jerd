import Foundation
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("App updates model")
@MainActor
struct AppUpdatesModelTests {
    @Test("Start reads the updater state once")
    func start() {
        let updater = InMemoryUpdater(
            initialState: AppUpdaterState(canCheck: true, automaticallyChecks: true, lastCheck: SampleData.now))
        let model = AppUpdatesModel(updater: updater)
        model.start()
        model.start()
        #expect(updater.startCount == 1)
        #expect(model.canCheckForUpdates)
        #expect(model.automaticallyChecks)
        #expect(model.lastCheck == SampleData.now)
    }

    @Test("An invalid configuration shows its error and the updater never starts")
    func invalidConfiguration() {
        let model = AppUpdatesModel(
            updater: InMemoryUpdater(startFailure: "The update feed URL is not the official feed."))
        model.start()
        #expect(!model.isStarted)
        #expect(model.errorMessage == "The update feed URL is not the official feed.")
        #expect(!model.canCheckForUpdates)
        #expect(!model.canChangePreferences)
    }

    @Test(
        "Events set the exact status line",
        arguments: [
            ([AppUpdateEvent.checkStarted], "Checking for app updates…", nil),
            ([.checkStarted, .updateFound("0.2.0")], "Jerd 0.2.0 is available.", nil),
            ([.checkStarted, .noUpdateFound], "No new app update is available for this Mac.", nil),
            (
                [.checkStarted, .cycleFinished(lastCheck: nil, result: .noUpdate)],
                "No new app update is available for this Mac.", nil
            ),
            ([.cycleFinished(lastCheck: nil, result: .cancelled)], "App update cancelled.", nil),
            (
                [.cycleFinished(lastCheck: nil, result: .failed("The network connection was lost."))],
                "The app update check did not finish.", "The network connection was lost."
            ),
        ] as [([AppUpdateEvent], String, String?)])
    func statusLine(events: [AppUpdateEvent], message: String, error: String?) {
        let updater = InMemoryUpdater()
        let model = AppUpdatesModel(updater: updater)
        model.start()
        events.forEach(updater.send)
        #expect(model.message == message)
        #expect(model.errorMessage == error)
    }

    @Test("While Jerd quits, no check starts and the preference cannot change")
    func terminating() {
        let updater = InMemoryUpdater()
        let model = AppUpdatesModel(updater: updater)
        model.start()
        model.isTerminating = true
        model.checkForUpdates()
        model.setAutomaticChecks(true)
        #expect(updater.checkCount == 0)
        #expect(updater.automaticCheckRequests.isEmpty)
        #expect(!model.allowsUpdateChecks)
        model.isTerminating = false
        model.checkForUpdates()
        model.setAutomaticChecks(true)
        #expect(updater.checkCount == 1)
        #expect(model.automaticallyChecks)
    }

    @Test("Sparkle can disable checks, for example during a running check")
    func canCheckEvent() {
        let updater = InMemoryUpdater()
        let model = AppUpdatesModel(updater: updater)
        model.start()
        updater.send(.canCheckChanged(false))
        #expect(!model.canCheckForUpdates)
    }

    @Test("App info reads missing bundle keys as Unknown")
    func appInfoFallbacks() {
        let info = AppInfo(bundle: Bundle(for: BundleToken.self))
        #expect(!info.version.isEmpty)
        #expect(!info.copyright.isEmpty)
        #expect(["Apple Silicon (arm64)", "Intel (x86_64)", "Unknown"].contains(info.architecture))
    }

    @Test("Credits keep their order and every address is a valid HTTPS URL")
    func credits() {
        #expect(Credit.all.first?.name == "PHP")
        #expect(Credit.all.last?.name == "Sparkle")
        #expect(Credit.all.count == 14)
        #expect(Credit.all.allSatisfy { $0.url?.scheme == "https" })
    }
}

private final class BundleToken {}

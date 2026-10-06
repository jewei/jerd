import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("App state lifecycle")
@MainActor
struct AppStateLifecycleTests {
    @Test("Launch loads every feature and page without any window, once")
    func launchWithoutWindow() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        await fixture.state.launch()
        #expect(fixture.state.isLaunched)
        #expect(fixture.shell.windowRequests == 0)
        #expect(fixture.features.allSatisfy { $0.launchCount == 1 })
        #expect(fixture.state.databases.loadState == .loaded)
        #expect(fixture.state.storage.loadState == .loaded)
        #expect(fixture.state.mail.loadState == .loaded)
        #expect(await fixture.services.mail.calls == ["load"])
        #expect(fixture.updater.startCount == 1)
        #expect(fixture.state.runtimes.inventory == SampleData.inventory)
        #expect(fixture.state.advanced.registrations == SampleData.registrations)
    }

    @Test("Launch applies the saved Dock and icon choices before any window shows")
    func launchAppliesPresence() async {
        let fixture = AppFixture { defaults in
            AppearanceDefaults(defaults).setShowDock(false)
            AppearanceDefaults(defaults).setIcon(.dots)
        }
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        #expect(fixture.shell.dockStates == [false])
        #expect(fixture.shell.icons == [.dots])
    }

    @Test("Reopen shows the window, the way back when menu bar and Dock are both off")
    func reopenShowsWindow() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        fixture.state.appearance.showMenuBar = false
        fixture.state.appearance.showDock = false
        fixture.state.reopen()
        #expect(fixture.shell.windowRequests == 1)
    }

    @Test("A successful quit stops every feature and replies true once")
    func quitSucceeds() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        var replies: [Bool] = []
        #expect(fixture.state.requestTermination { replies.append($0) } == .later)
        #expect(fixture.state.appUpdates.isTerminating)
        await waitUntil { !replies.isEmpty }
        #expect(replies == [true])
        #expect(fixture.features.allSatisfy { $0.shutdownCount == 1 })
        #expect(fixture.state.requestTermination { replies.append($0) } == .now)
    }

    @Test("A second quit request during the quit is cancelled at once; the first gets one reply")
    func duplicateRequest() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        var replies: [Bool] = []
        #expect(fixture.state.requestTermination { replies.append($0) } == .later)
        await waitUntil { fixture.state.shutdown.message == ShutdownPhase.storage.message }
        #expect(fixture.state.requestTermination { replies.append($0) } == .cancel)
        #expect(replies.isEmpty)
    }

    @Test("A failed stage keeps Jerd open, shows the failing feature, and alerts once")
    func quitCancelled() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.services.databases.configure { $0.stopBehavior = .fail("MySQL did not stop.") }
        await fixture.state.launch()
        var replies: [Bool] = []
        _ = fixture.state.requestTermination { replies.append($0) }
        await waitUntil { !replies.isEmpty }
        #expect(replies == [false])
        #expect(fixture.state.navigation.section == .databases)
        #expect(fixture.state.alert == .quitCancelled(ShutdownPhase.databases.failureMessage))
        #expect(!fixture.state.appUpdates.isTerminating)
        #expect(fixture.shell.windowRequests == 1)
        let web = fixture.features.first { $0.section == .sites }
        #expect(web?.shutdownCount == 0)
        #expect(!fixture.state.storage.isShuttingDown)
        #expect(!fixture.state.mail.isShuttingDown)
        #expect(fixture.state.requestTermination { _ in } == .later)
    }

    @Test("The banner shows the quit stage first, then feature work")
    func bannerActivity() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        #expect(fixture.state.bannerActivity == nil)
        fixture.features[0].bannerActivity = BannerActivity(message: "Stopping sites…")
        #expect(fixture.state.bannerActivity?.message == "Stopping sites…")
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        _ = fixture.state.requestTermination { _ in }
        await waitUntil { fixture.state.shutdown.message == ShutdownPhase.storage.message }
        #expect(fixture.state.bannerActivity?.message == "Stopping storage…")
    }

    @Test("Opening a destination navigates and brings the window forward")
    func openDestination() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        fixture.state.open(.dashboard(.about))
        #expect(fixture.state.navigation.section == .dashboard)
        #expect(fixture.state.navigation.dashboardPage == .about)
        #expect(fixture.shell.windowRequests == 1)
    }

    @Test("Copy writes the pasteboard and sets the window-level confirmation")
    func copyFeedback() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        fixture.state.clipboard.copy("https://studio.test", confirmation: "Copied site URL")
        #expect(fixture.shell.pasteboard == ["https://studio.test"])
        #expect(fixture.state.clipboard.feedback?.text == "Copied site URL")
    }
}

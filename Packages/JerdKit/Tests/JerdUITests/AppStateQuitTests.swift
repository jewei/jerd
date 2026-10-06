import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("App state quit during launch and repeated quit requests")
@MainActor
struct AppStateQuitTests {
    private func sites(_ fixture: AppFixture) -> InMemoryFeature? {
        fixture.features.first { $0.section == .sites }
    }

    @Test("Two quit requests in one main-actor turn start one quit; the second is cancelled at once")
    func twoRequestsInOneTurn() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        var replies: [String] = []
        let first = fixture.state.requestTermination { replies.append("first:\($0)") }
        let second = fixture.state.requestTermination { replies.append("second:\($0)") }
        #expect(first == .later)
        #expect(second == .cancel)
        await waitUntil { fixture.state.shutdown.message == ShutdownPhase.storage.message }
        for _ in 0..<50 { await Task.yield() }
        #expect(replies.isEmpty)
        #expect(await fixture.services.storage.calls.filter { $0 == "stop" }.count == 1)
        #expect(fixture.state.isQuitting)
    }

    @Test("A quit during launch waits for the launching feature; later features never launch")
    func quitWaitsForLaunch() async {
        let journal = CallJournal()
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        sites(fixture)?.journal = journal
        sites(fixture)?.holdsLaunch = true
        let launch = Task { await fixture.state.launch() }
        await waitUntil { journal.entries == ["sites.launch"] }
        var replies: [Bool] = []
        #expect(fixture.state.requestTermination { replies.append($0) } == .later)
        #expect(fixture.state.bannerActivity?.message == ShutdownCoordinator.launchMessage)
        for _ in 0..<50 { await Task.yield() }
        #expect(journal.entries == ["sites.launch"])
        #expect(replies.isEmpty)
        sites(fixture)?.holdsLaunch = false
        await waitUntil { !replies.isEmpty }
        await launch.value
        #expect(replies == [true])
        #expect(journal.entries == ["sites.launch", "sites.launched", "sites.shutdown"])
        #expect(await fixture.services.databases.calls.isEmpty)
        #expect(await fixture.services.mail.calls.isEmpty)
        #expect(!fixture.state.isLaunched)
        #expect(fixture.state.pollers.allSatisfy { !$0.isRunning })
    }

    @Test("A cancelled quit during launch lets the launch finish")
    func cancelledQuitResumesLaunch() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        sites(fixture)?.holdsLaunch = true
        sites(fixture)?.stopsSafely = false
        let launch = Task { await fixture.state.launch() }
        await waitUntil { sites(fixture)?.launchCount == 1 }
        var replies: [Bool] = []
        _ = fixture.state.requestTermination { replies.append($0) }
        sites(fixture)?.holdsLaunch = false
        await waitUntil { !replies.isEmpty }
        await launch.value
        await fixture.state.launch()
        #expect(replies == [false])
        #expect(fixture.state.isLaunched)
        #expect(sites(fixture)?.launchCount == 1)
        #expect(await fixture.services.mail.calls == ["load"])
        #expect(!fixture.state.isQuitting)
        fixture.state.pollers.forEach { $0.stop() }
    }

    @Test("A feature that did not launch takes no part in the quit")
    func unlaunchedFeatureNotStopped() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        var replies: [Bool] = []
        _ = fixture.state.requestTermination { replies.append($0) }
        await waitUntil { !replies.isEmpty }
        #expect(replies == [true])
        #expect(sites(fixture)?.shutdownCount == 0)
        #expect(await fixture.services.storage.calls.isEmpty)
        await fixture.state.launch()
        #expect(sites(fixture)?.launchCount == 0)
        #expect(await fixture.services.mail.calls.isEmpty)
    }
}

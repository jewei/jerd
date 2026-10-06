import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("App state quit during launch and repeated quit requests")
@MainActor
struct AppStateQuitTests {
    private func feature(_ fixture: AppFixture, _ section: AppSection) -> InMemoryFeature? {
        fixture.features.first { $0.section == section }
    }

    @Test("Two quit requests in one main-actor turn start one quit; the second is cancelled at once")
    func twoRequestsInOneTurn() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        feature(fixture, .storage)?.stopsSafely = nil
        var replies: [String] = []
        let first = fixture.state.requestTermination { replies.append("first:\($0)") }
        let second = fixture.state.requestTermination { replies.append("second:\($0)") }
        #expect(first == .later)
        #expect(second == .cancel)
        await waitUntil { fixture.state.shutdown.message == ShutdownPhase.storage.message }
        for _ in 0..<50 { await Task.yield() }
        #expect(replies.isEmpty)
        #expect(feature(fixture, .storage)?.shutdownCount == 1)
        #expect(fixture.state.isQuitting)
    }

    @Test("A quit during launch waits for the launching feature; later features never launch")
    func quitWaitsForLaunch() async {
        let journal = CallJournal()
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        fixture.features.forEach { $0.journal = journal }
        feature(fixture, .sites)?.holdsLaunch = true
        let launch = Task { await fixture.state.launch() }
        await waitUntil { journal.entries == ["sites.launch"] }
        var replies: [Bool] = []
        #expect(fixture.state.requestTermination { replies.append($0) } == .later)
        #expect(fixture.state.bannerActivity?.message == ShutdownCoordinator.launchMessage)
        for _ in 0..<50 { await Task.yield() }
        #expect(journal.entries == ["sites.launch"])
        #expect(replies.isEmpty)
        feature(fixture, .sites)?.holdsLaunch = false
        await waitUntil { !replies.isEmpty }
        await launch.value
        #expect(replies == [true])
        #expect(journal.entries == ["sites.launch", "sites.launched", "sites.shutdown"])
        #expect(!fixture.state.isLaunched)
        #expect(fixture.state.pollers.allSatisfy { !$0.isRunning })
    }

    @Test("A cancelled quit during launch lets the launch finish")
    func cancelledQuitResumesLaunch() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        feature(fixture, .sites)?.holdsLaunch = true
        feature(fixture, .sites)?.stopsSafely = false
        let launch = Task { await fixture.state.launch() }
        await waitUntil { feature(fixture, .sites)?.launchCount == 1 }
        var replies: [Bool] = []
        _ = fixture.state.requestTermination { replies.append($0) }
        feature(fixture, .sites)?.holdsLaunch = false
        await waitUntil { !replies.isEmpty }
        await launch.value
        await fixture.state.launch()
        #expect(replies == [false])
        #expect(fixture.state.isLaunched)
        #expect(fixture.features.allSatisfy { $0.launchCount == 1 })
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
        #expect(fixture.features.allSatisfy { $0.shutdownCount == 0 })
        await fixture.state.launch()
        #expect(fixture.features.allSatisfy { $0.launchCount == 0 })
    }
}

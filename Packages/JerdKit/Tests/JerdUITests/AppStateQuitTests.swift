import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("App state quit during launch and repeated quit requests")
@MainActor
struct AppStateQuitTests {
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
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.sites.configure { $0.holdsLoad = true }
        let launch = Task { await fixture.state.launch() }
        for _ in 0..<1_000 where await !fixture.sites.calls.contains("load") { await Task.yield() }
        var replies: [Bool] = []
        #expect(fixture.state.requestTermination { replies.append($0) } == .later)
        #expect(fixture.state.bannerActivity?.message == ShutdownCoordinator.launchMessage)
        for _ in 0..<50 { await Task.yield() }
        #expect(await fixture.sites.calls == ["load"])
        #expect(replies.isEmpty)
        await fixture.sites.releaseLoad()
        await waitUntil { !replies.isEmpty }
        await launch.value
        #expect(replies == [true])
        #expect(await fixture.sites.calls == ["load", "stop environment"])
        #expect(await fixture.services.databases.calls.isEmpty)
        #expect(await fixture.services.mail.calls.isEmpty)
        #expect(!fixture.state.isLaunched)
        #expect(fixture.state.pollers.allSatisfy { !$0.isRunning })
    }

    @Test("A cancelled quit during launch lets the launch finish")
    func cancelledQuitResumesLaunch() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.sites.configure { $0.holdsLoad = true }
        let launch = Task { await fixture.state.launch() }
        for _ in 0..<1_000 where await !fixture.sites.calls.contains("load") { await Task.yield() }
        var replies: [Bool] = []
        _ = fixture.state.requestTermination { replies.append($0) }
        await fixture.sites.configure { $0.failure = "Caddy did not stop." }
        await fixture.sites.releaseLoad()
        await waitUntil { !replies.isEmpty }
        await launch.value
        await fixture.state.launch()
        #expect(replies == [false])
        #expect(fixture.state.isLaunched)
        #expect(await fixture.sites.calls.filter { $0 == "load" }.count == 1)
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
        #expect(await fixture.sites.calls.isEmpty)
        #expect(await fixture.services.storage.calls.isEmpty)
        await fixture.state.launch()
        #expect(await fixture.sites.calls.isEmpty)
        #expect(await fixture.services.mail.calls.isEmpty)
    }
}

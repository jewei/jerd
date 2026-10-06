import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Service poller")
@MainActor
struct ServicePollerTests {
    private let policy = PollingPolicy(visibleInterval: .milliseconds(700), backgroundInterval: .seconds(5))
    private let visible = AppActivity(isActive: true, isWindowVisible: true)

    @Test(
        "Polling is fast only while live state is on screen",
        arguments: [
            (AppActivity(isActive: true, isWindowVisible: true), true),
            (AppActivity(isActive: false, isWindowVisible: true), false),
            (AppActivity(isActive: true, isWindowVisible: false), false),
            (AppActivity(isMenuOpen: true), true),
            (AppActivity(), false),
        ])
    func intervalRule(activity: AppActivity, isFast: Bool) {
        #expect(policy.interval(for: activity) == (isFast ? .milliseconds(700) : .seconds(5)))
    }

    @Test("A background interval is never shorter than the visible interval")
    func backgroundNotShorter() {
        let odd = PollingPolicy(visibleInterval: .seconds(2), backgroundInterval: .seconds(1))
        #expect(odd.backgroundInterval == .seconds(2))
    }

    @Test("The poller refreshes after each interval of the current activity")
    func refreshesPerInterval() async {
        let sleeper = RecordingSleeper(allowedSleeps: 3)
        var refreshes = 0
        let poller = ServicePoller(policy: policy, sleeper: sleeper) { refreshes += 1 }
        poller.start(activity: visible)
        await waitUntil { refreshes == 3 }
        #expect(refreshes == 3)
        #expect(sleeper.durations.prefix(3) == [.milliseconds(700), .milliseconds(700), .milliseconds(700)])
        poller.stop()
    }

    @Test("A hidden window slows polling; showing it refreshes at once")
    func activityChanges() async {
        let sleeper = RecordingSleeper(allowedSleeps: 0)
        var refreshes = 0
        let poller = ServicePoller(policy: policy, sleeper: sleeper) { refreshes += 1 }
        poller.start(activity: AppActivity())
        await waitUntil { sleeper.durations.count == 1 }
        #expect(sleeper.durations == [.seconds(5)])
        poller.update(activity: visible)
        await waitUntil { refreshes == 1 && sleeper.durations.count == 2 }
        #expect(refreshes == 1)
        #expect(sleeper.durations.last == .milliseconds(700))
        poller.stop()
    }

    @Test("A faster pace during a refresh waits for that refresh; two refreshes never overlap")
    func refreshesNeverOverlap() async {
        let sleeper = RecordingSleeper(allowedSleeps: 1)
        var isHeld = true
        var running = 0
        var mostAtOnce = 0
        var refreshes = 0
        let poller = ServicePoller(policy: policy, sleeper: sleeper) {
            running += 1
            mostAtOnce = max(mostAtOnce, running)
            refreshes += 1
            while isHeld { await Task.yield() }
            running -= 1
        }
        poller.start(activity: AppActivity())
        await waitUntil { refreshes == 1 }
        poller.update(activity: visible)
        for _ in 0..<50 { await Task.yield() }
        #expect(refreshes == 1)
        isHeld = false
        await waitUntil { refreshes == 2 }
        #expect(refreshes == 2)
        #expect(mostAtOnce == 1)
        poller.stop()
    }

    @Test("A longer interval does not restart the loop or refresh")
    func slowerActivityWaits() async {
        let sleeper = RecordingSleeper(allowedSleeps: 0)
        var refreshes = 0
        let poller = ServicePoller(policy: policy, sleeper: sleeper) { refreshes += 1 }
        poller.start(activity: visible)
        await waitUntil { sleeper.durations.count == 1 }
        poller.update(activity: AppActivity())
        await Task.yield()
        #expect(refreshes == 0)
        #expect(sleeper.durations == [.milliseconds(700)])
        poller.stop()
    }

    @Test("After stop, the poller never refreshes or starts again")
    func stopIsFinal() async {
        let sleeper = RecordingSleeper(allowedSleeps: 0)
        var refreshes = 0
        let poller = ServicePoller(policy: policy, sleeper: sleeper) { refreshes += 1 }
        poller.start(activity: visible)
        poller.stop()
        sleeper.allow(5)
        poller.start(activity: visible)
        poller.update(activity: AppActivity(isMenuOpen: true))
        for _ in 0..<50 { await Task.yield() }
        #expect(!poller.isRunning)
        #expect(refreshes == 0)
    }

    @Test("When the window shows in the active app, every feature refreshes at once")
    func appStateForwardsActivity() async {
        let sleeper = RecordingSleeper(allowedSleeps: 0)
        let fixture = AppFixture(sleeper: sleeper)
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        #expect(fixture.features.allSatisfy { $0.refreshCount == 0 })
        fixture.state.setAppActive(true)
        fixture.state.setWindowVisible(true)
        await waitUntil { fixture.features.allSatisfy { $0.refreshCount == 1 } }
        #expect(fixture.features.allSatisfy { $0.refreshCount == 1 })
        #expect(fixture.state.activity == AppActivity(isActive: true, isWindowVisible: true))
        fixture.state.pollers.forEach { $0.stop() }
    }

    @Test("A successful quit stops polling for good")
    func quitStopsPolling() async {
        let fixture = AppFixture(sleeper: RecordingSleeper(allowedSleeps: 0))
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        var replied = false
        _ = fixture.state.requestTermination { _ in replied = true }
        await waitUntil { replied }
        #expect(fixture.state.pollers.allSatisfy { !$0.isRunning })
    }
}

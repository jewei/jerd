import Testing

@testable import JerdDevKit

@Suite("Update case expectations")
struct UpdateCaseTests {
    @Test("Each case passes with the events that Sparkle writes", arguments: UpdateCase.allCases)
    func passes(_ testCase: UpdateCase) {
        let expected = UpdateEvents.expected(for: testCase)
        #expect(testCase.failures(events: expected.events, installedVersion: expected.version).isEmpty)
        #expect(UpdateCase.isComplete(expected.events))
    }

    @Test("The cases run in the order of the old harness and keep their names")
    func order() {
        #expect(
            UpdateCase.allCases.map(\.rawValue) == [
                "no-update", "altered-feed", "altered-archive", "success", "refused-quit",
            ])
    }

    @Test("An installation that did not replace version 1 fails")
    func successNeedsVersionTwo() {
        let events = UpdateEvents.text(UpdateEvents.success)
        #expect(
            UpdateCase.success.failures(events: events, installedVersion: "1") == [
                "The installed app is not version 2."
            ])
    }

    @Test("Version 2 must not start before version 1 approved its quit")
    func quitComesFirst() {
        let lines = ["pid:101", "launched:1", "found:2"] + UpdateEvents.relaunched + ["quit-approved:1"]
        let failures = UpdateCase.success.failures(events: UpdateEvents.text(lines), installedVersion: "2")
        #expect(failures == ["Version 2 started before version 1 quit."])
    }

    @Test("A refused quit must keep version 1 until the retry")
    func refusalKeepsVersionOne() {
        let lines = UpdateEvents.refusedQuit.map { $0 == "version-after-refusal:1" ? "version-after-refusal:2" : $0 }
        let failures = UpdateCase.refusedQuit.failures(events: UpdateEvents.text(lines), installedVersion: "2")
        #expect(failures == ["Sparkle replaced the app after a refused quit."])
    }

    @Test("An altered feed must fail before any item is found")
    func alteredFeedFindsNothing() {
        let lines = UpdateEvents.alteredFeed + ["found:9"]
        let failures = UpdateCase.alteredFeed.failures(events: UpdateEvents.text(lines), installedVersion: "1")
        #expect(failures == ["Sparkle accepted an item of the altered feed."])
    }

    @Test("An altered archive must fail with a signature error and never get ready")
    func alteredArchiveNeverReady() {
        let lines = ["pid:101", "launched:1", "found:2", "ready", "failed"]
        let failures = UpdateCase.alteredArchive.failures(events: UpdateEvents.text(lines), installedVersion: "1")
        #expect(
            failures == ["Sparkle prepared an installation.", "Sparkle did not report an EdDSA signature mismatch."])
    }

    @Test("A case without an update must not change the app")
    func noUpdateKeepsApp() {
        let failures = UpdateCase.noUpdate.failures(events: "launched:1\n", installedVersion: "2")
        #expect(failures == ["Sparkle did not report that no update exists.", "The installed app changed."])
    }

    @Test("A run is complete only after its final event")
    func completion() {
        #expect(!UpdateCase.isComplete(UpdateEvents.text(UpdateEvents.installed)))
        #expect(!UpdateCase.isComplete("quit-approved:1\n"))
    }
}

import Foundation
import JerdFoundation
import Testing

@testable import JerdLive

/// A Debug run on another data root leaves the user's
/// `dev.jerd.app` preferences as they were, also the keys that AppKit and SwiftUI write.
@Suite("Preference guard")
@MainActor
struct PreferenceGuardTests {
    final class FakeDomain: PreferenceDomain {
        var values: [String: Any]
        private(set) var writes: [String] = []

        init(_ values: [String: Any]) { self.values = values }

        func read() -> [String: Any] { values }
        func write(_ value: Any, for key: String) {
            values[key] = value
            writes.append(key)
        }
        func remove(_ key: String) { values[key] = nil }
    }

    @Test("The status item, window frame, and split keys get their old values back at quit")
    func restoresWhatAppKitChanged() {
        let domain = FakeDomain([
            "NSStatusItem VisibleCC Item-0": false,
            "NSWindow Frame main": "55 85 1220 660 0 0 1470 922 ",
            "showMenuBar": false,
            "NSSplitView Subview Frames main, SidebarNavigationSplitView": ["0, 0, 240, 660, NO, NO"],
        ])
        let guarded = PreferenceGuard(domain: domain)
        domain.values["NSStatusItem VisibleCC Item-0"] = true
        domain.values["NSWindow Frame main"] = "393 325 1220 660 0 0 3008 1661 "
        domain.values["NSSplitView Subview Frames main, SidebarNavigationSplitView"] = ["0, 0, 260, 660, NO, NO"]
        domain.values["SULastCheckTime"] = Date()
        domain.values["showMenuBar"] = nil

        guarded.restore()

        #expect(domain.values["NSStatusItem VisibleCC Item-0"] as? Bool == false)
        #expect(domain.values["NSWindow Frame main"] as? String == "55 85 1220 660 0 0 1470 922 ")
        #expect(
            domain.values["NSSplitView Subview Frames main, SidebarNavigationSplitView"] as? [String] == [
                "0, 0, 240, 660, NO, NO"
            ])
        #expect(domain.values["SULastCheckTime"] == nil)
        #expect(domain.values["showMenuBar"] as? Bool == false)
    }

    @Test("Keys that did not change are not written")
    func writesOnlyChangedKeys() {
        let domain = FakeDomain(["appIcon": "original", "NSWindow Frame main": "1 2 3 4"])
        let guarded = PreferenceGuard(domain: domain)
        domain.values["NSWindow Frame main"] = "5 6 7 8"
        guarded.restore()
        #expect(domain.writes == ["NSWindow Frame main"])
    }

    @Test("Only a run on another data root gets a guard; the user's own run keeps its window state")
    func onlyOtherDataRootsAreGuarded() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let other = try LiveAppTests.configuration(in: temporary)
        #expect(PreferenceGuard.forRun(other, domainName: "dev.jerd.live-tests.guard") != nil)
        let user = LiveConfiguration(
            layout: .currentUser(), appBundle: other.appBundle, resources: other.resources, appVersion: nil)
        #expect(PreferenceGuard.forRun(user, domainName: "dev.jerd.live-tests.guard") == nil)
    }
}

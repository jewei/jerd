import Foundation
import JerdManifest
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Copy, accessibility, and fixture hygiene")
@MainActor
struct CopyConsistencyTests {
    @Test("The update check has one title everywhere, with an ellipsis because it opens a window")
    func oneCheckTitle() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        #expect(AppUpdatesModel.checkTitle == "Check for Updates…")
        #expect(AppCommand.checkForUpdates.title(in: fixture.state) == AppUpdatesModel.checkTitle)
        let items = MenuBarMenu.items(for: fixture.state) {}
        #expect(items.contains { $0.title == AppUpdatesModel.checkTitle })
    }

    @Test("The Runtimes check and the app update check have different visible titles")
    func runtimeCheckTitleDiffers() {
        #expect(RuntimeCopy.checkTitle == "Check for Runtime Updates")
        #expect(RuntimeCopy.checkTitle != AppUpdatesModel.checkTitle)
        #expect(!AppUpdatesModel.checkTitle.hasPrefix(RuntimeCopy.checkTitle))
        #expect(RuntimeCopy.notCheckedMessage.contains("Select \(RuntimeCopy.checkTitle) "))
    }

    @Test("Every sidebar footer uses one caption rule: none when empty, running only when it runs")
    func sidebarCaption() {
        #expect(SidebarCaption.text(count: 0, singular: "site", plural: "sites", running: 0) == nil)
        #expect(SidebarCaption.text(count: 0, singular: "bucket", plural: "buckets") == nil)
        #expect(SidebarCaption.text(count: 1, singular: "service", plural: "services", running: 0) == "1 service")
        #expect(SidebarCaption.text(count: 3, singular: "site", plural: "sites", running: 2) == "3 sites · 2 running")
        #expect(SidebarCaption.text(count: 2, singular: "bucket", plural: "buckets") == "2 buckets")
    }

    @Test("A site that needs HTTPS setup shows one tone: the header status and the banner match")
    func setupRequiredHasOneTone() {
        let header = SiteStatusPolicy.environment(.setupRequired)
        let banner = SystemSetupState.approvalRequired.kind
        #expect(header.tone == .attention)
        #expect(banner == .warning)
        #expect(banner.systemImage == header.tone.systemImage)
    }

    @Test("The release picker shows the version only; the Installed label marks an installed release")
    func releaseLabel() {
        let release = SampleData.release(.caddy, "2.10.2")
        #expect(RuntimeCopy.releaseLabel(release) == release.versionLabel)
    }

    @Test("Before the first check the page says it once; a section footer never repeats it")
    func notCheckedOnce() {
        #expect(RuntimeCopy.notCheckedMessage.hasPrefix("Updates have not been checked."))
        for kind in RuntimeKind.allCases {
            #expect(RuntimeCopy.footer(kind, checkedAt: nil)?.contains("not been checked") != true)
        }
    }

    @Test("A credit link speaks the project name only; the row value speaks the role")
    func creditLabel() {
        for credit in Credit.all {
            #expect(CreditsSection.linkLabel(credit) == credit.name)
        }
    }

    @Test("A fixture or snapshot scenario writes no defaults domain to disk", arguments: FixtureScenario.allCases)
    func noDefaultsLeft(scenario: FixtureScenario) {
        let fixture = scenario.makeFixture()
        #expect(fixture.defaults is InMemoryDefaults)
        #expect(UserDefaults.standard.persistentDomain(forName: fixture.suiteName) == nil)
        let preferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(fixture.suiteName).plist")
        #expect(!FileManager.default.fileExists(atPath: preferences.path))
    }
}

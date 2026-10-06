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

import JerdUIFixtures
import SwiftUI
import Testing

@testable import JerdUI

@Suite("Commands and menu bar")
@MainActor
struct CommandsAndMenuTests {
    @Test("Section shortcuts are ⌘1 to ⌘5 in section order, and each opens its section")
    func sectionShortcuts() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        for section in AppSection.allCases {
            let command = AppCommand.showSection(section)
            #expect(command.shortcut == CommandShortcut(Character("\(section.rawValue + 1)"), modifiers: .command))
            command.perform(in: fixture.state)
            #expect(fixture.state.navigation.section == section)
        }
    }

    @Test("Settings… is ⌘, and opens Appearance; About opens About")
    func settingsAndAbout() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        #expect(AppCommand.settings.shortcut == CommandShortcut(",", modifiers: .command))
        AppCommand.settings.perform(in: fixture.state)
        #expect(fixture.state.navigation.dashboardPage == .appearance)
        AppCommand.about.perform(in: fixture.state)
        #expect(fixture.state.navigation.dashboardPage == .about)
        #expect(fixture.shell.windowRequests == 2)
    }

    @Test("⌃⌘S shows and hides the sidebar of the current section, and is off on Mail")
    func sidebarCommand() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        #expect(AppCommand.toggleSidebar.shortcut == CommandShortcut("s", modifiers: [.command, .control]))
        #expect(AppCommand.toggleSidebar.title(in: state) == "Hide Sidebar")
        AppCommand.toggleSidebar.perform(in: state)
        #expect(AppCommand.toggleSidebar.title(in: state) == "Show Sidebar")
        state.navigation.show(.section(.mail))
        #expect(!AppCommand.toggleSidebar.isEnabled(in: state))
    }

    @Test("Check for Updates… follows the updater")
    func checkCommand() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        #expect(!AppCommand.checkForUpdates.isEnabled(in: fixture.state))
        fixture.state.appUpdates.start()
        #expect(AppCommand.checkForUpdates.isEnabled(in: fixture.state))
        AppCommand.checkForUpdates.perform(in: fixture.state)
        #expect(fixture.updater.checkCount == 1)
    }

    @Test("No two commands share a shortcut")
    func uniqueShortcuts() {
        let shortcuts = AppCommand.all.compactMap(\.shortcut)
        for (index, shortcut) in shortcuts.enumerated() {
            #expect(!shortcuts[(index + 1)...].contains(shortcut))
        }
    }

    @Test("The menu bar menu has open items, feature entries, app commands, and Quit, in order")
    func menuTree() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        var quits = 0
        let items = MenuBarMenu.items(for: fixture.state) { quits += 1 }
        let titles = items.compactMap(\.title)
        #expect(
            Array(titles.prefix(5)) == ["Open Jerd", "Open Sites", "Open Databases", "Open Storage", "Open Mail"])
        #expect(titles.contains("Open Studio"))
        #expect(Array(titles.suffix(4)) == ["Settings…", "About Jerd", "Check for Updates…", "Quit Jerd"])
        #expect(items.last?.shortcut == CommandShortcut("q", modifiers: .command))
        if case .action(let quit) = items.last?.kind { quit.perform() }
        #expect(quits == 1)
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test("Menu open items show the section in the window")
    func menuOpens() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        let items = MenuBarMenu.items(for: fixture.state) {}
        let openMail = items.first { $0.id == "menu.open.mail" }
        if case .action(let action) = openMail?.kind { action.perform() }
        #expect(fixture.state.navigation.section == .mail)
        #expect(fixture.shell.windowRequests == 1)
    }

    @Test("The dashboard shows a card per service in order, and a placeholder for a missing feature")
    func dashboardCards() {
        let fixture = AppFixture(features: [])
        defer { fixture.removeDefaults() }
        #expect(DashboardCards.sections == [.sites, .databases, .storage, .mail])
        #expect(DashboardCards.summary(for: .sites, in: fixture.state).summary == "Built in the next work package.")
        #expect(RuntimesSummaryRow.detail(defaultPHP: nil) == "View installed versions and check for updates.")
        #expect(
            RuntimesSummaryRow.detail(defaultPHP: RegisteredPHP(id: SampleData.php84ID, version: "8.4.12"))
                == "PHP 8.4.12 is the default. View installed versions and check for updates.")
    }
}

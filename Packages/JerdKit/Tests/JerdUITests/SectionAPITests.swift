import Foundation
import JerdDesign
import JerdUIFixtures
import SwiftUI
import Testing

@testable import JerdUI

@Suite("Section API for feature packages")
@MainActor
struct SectionAPITests {
    private func sites(_ fixture: AppFixture) -> InMemoryFeature? {
        fixture.features.first { $0.section == .sites }
    }

    @Test("File › New (⌘N) runs the New command of the current section, also with the sidebar hidden")
    func newItemCommand() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        var added = 0
        sites(fixture)?.newItemAction = FeatureAction(id: "sites.new", title: "New Site…") { added += 1 }
        let state = fixture.state
        #expect(AppCommand.newItem.shortcut == CommandShortcut("n", modifiers: .command))
        state.navigation.show(.section(.sites))
        state.navigation.toggleSidebar()
        #expect(!state.navigation.isSidebarVisible(in: .sites))
        #expect(AppCommand.newItem.title(in: state) == "New Site…")
        #expect(AppCommand.newItem.isEnabled(in: state))
        AppCommand.newItem.perform(in: state)
        #expect(added == 1)

        state.navigation.show(.dashboard(.overview))
        #expect(AppCommand.newItem.title(in: state) == "New…")
        #expect(!AppCommand.newItem.isEnabled(in: state))
        AppCommand.newItem.perform(in: state)
        #expect(added == 1)
    }

    @Test("File › New is off when the section turns its command off, and during a quit")
    func newItemDisabled() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        var added = 0
        let feature = sites(fixture)
        feature?.newItemAction = FeatureAction(id: "sites.new", title: "New Site…", isEnabled: false) { added += 1 }
        fixture.state.navigation.show(.section(.sites))
        #expect(!AppCommand.newItem.isEnabled(in: fixture.state))
        feature?.newItemAction = FeatureAction(id: "sites.new", title: "New Site…") { added += 1 }
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        _ = fixture.state.requestTermination { _ in }
        #expect(!AppCommand.newItem.isEnabled(in: fixture.state))
        AppCommand.newItem.perform(in: fixture.state)
        #expect(added == 0)
    }

    @Test("A feature can poll two kinds of state at their own pace")
    func twoPollingLoops() async {
        let sleeper = RecordingSleeper(allowedSleeps: 0)
        let feature = SampleFeatures.all(.populated)[0]
        feature.pollingPolicy = .environment
        feature.extraPollingPolicies = [.tunnels]
        let fixture = AppFixture(features: [feature], sleeper: sleeper)
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        fixture.state.setAppActive(true)
        fixture.state.setWindowVisible(true)
        await waitUntil { feature.refreshCount == 1 && feature.extraRefreshCount == 1 }
        #expect(feature.refreshCount == 1)
        #expect(feature.extraRefreshCount == 1)
        #expect(sleeper.durations.contains(.milliseconds(500)))
        #expect(sleeper.durations.contains(.seconds(1)))
        fixture.state.pollers.forEach { $0.stop() }
    }

    @Test("The sidebar toggle names its action, and on Mail it is off and says why")
    func sidebarToggle() {
        var navigation = NavigationState(section: .sites)
        #expect(SidebarToggle.title(for: navigation) == "Hide Sidebar")
        #expect(SidebarToggle.help(for: navigation) == "Hide Sidebar (⌃⌘S)")
        navigation.toggleSidebar()
        #expect(SidebarToggle.title(for: navigation) == "Show Sidebar")
        navigation.show(.section(.mail))
        #expect(!navigation.canToggleSidebar)
        #expect(SidebarToggle.help(for: navigation) == "Mail has no sidebar")
    }

    @Test("The sidebar selection binding keeps the user's selection through list refreshes")
    func selectionBinding() {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        state.navigation.show(.section(.databases))
        let binding = state.sidebarSelection(in: .databases)
        let database = SidebarSelection.database(UUIDs.first)
        binding.wrappedValue = database
        binding.wrappedValue = nil
        binding.wrappedValue = .bucket("assets")
        #expect(binding.wrappedValue == database)
        #expect(state.navigation.selection(in: .databases) == database)
    }
}

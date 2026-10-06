import Foundation
import Testing

@testable import JerdUI

@Suite("Navigation state")
struct NavigationStateTests {
    @Test("Sections keep the approved order and titles")
    func sectionOrder() {
        #expect(AppSection.allCases.map(\.title) == ["Dashboard", "Sites", "Databases", "Storage", "Mail"])
        #expect(AppSection.allCases.map(\.shortcutKey) == ["1", "2", "3", "4", "5"])
        #expect(DashboardPage.allCases.map(\.title) == ["Dashboard", "Appearance", "Runtimes", "Advanced", "About"])
    }

    @Test(
        "Showing a destination selects its section and page or item",
        arguments: [
            (Destination.section(.storage), AppSection.storage),
            (.dashboard(.runtimes), .dashboard),
            (.item(.site(UUID())), .sites),
            (.item(.tunnel(UUID())), .sites),
            (.item(.database(UUID())), .databases),
            (.item(.bucket("uploads")), .storage),
        ])
    func showDestination(destination: Destination, section: AppSection) {
        var state = NavigationState()
        state.show(destination)
        #expect(state.section == section)
        if case .item(let item) = destination {
            #expect(state.selection(in: section) == item)
        }
        if case .dashboard(let page) = destination {
            #expect(state.dashboardPage == page)
        }
    }

    @Test("A section change keeps the dashboard page and the selections of other sections")
    func sectionChangeKeepsState() {
        var state = NavigationState()
        let site = SidebarSelection.site(UUID())
        state.show(.dashboard(.advanced))
        state.show(.item(site))
        state.show(.section(.mail))
        state.show(.section(.dashboard))
        #expect(state.dashboardPage == .advanced)
        #expect(state.selection(in: .sites) == site)
    }

    @Test("A list refresh with nil or an item of another section never clears the selection")
    func listSelectionGuards() {
        var state = NavigationState()
        let site = SidebarSelection.site(UUID())
        state.show(.item(site))
        state.select(nil)
        state.select(.bucket("uploads"))
        #expect(state.selection(in: .sites) == site)
        #expect(state.selection(in: .storage) == nil)
        let tunnel = SidebarSelection.tunnel(UUID())
        state.select(tunnel)
        #expect(state.selection(in: .sites) == tunnel)
        state.clearSelection(in: .sites)
        #expect(state.selection(in: .sites) == nil)
    }

    @Test("Each section remembers its own sidebar state")
    func perSectionSidebar() {
        var state = NavigationState()
        state.toggleSidebar()
        #expect(!state.isSidebarVisible(in: .dashboard))
        state.show(.section(.sites))
        #expect(state.isSidebarVisible(in: .sites))
        state.setSidebarVisible(false)
        state.show(.section(.dashboard))
        #expect(!state.isSidebarVisible(in: .dashboard))
        state.toggleSidebar()
        #expect(state.isSidebarVisible(in: .dashboard))
        #expect(!state.isSidebarVisible(in: .sites))
    }

    @Test("Mail never has a sidebar, and its toggle does nothing")
    func mailHasNoSidebar() {
        var state = NavigationState(section: .mail)
        #expect(!state.canToggleSidebar)
        state.toggleSidebar()
        state.setSidebarVisible(true)
        #expect(!state.isSidebarVisible(in: .mail))
    }
}

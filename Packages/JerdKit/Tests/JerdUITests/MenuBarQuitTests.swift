import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Menu bar menu and cards during a quit")
@MainActor
struct MenuBarQuitTests {
    /// Every action in the tree, also inside submenus.
    private func actions(_ items: [MenuBarItem]) -> [FeatureAction] {
        items.flatMap { item -> [FeatureAction] in
            switch item.kind {
            case .action(let action): [action]
            case .submenu(_, let children): actions(children)
            case .text, .divider: []
            }
        }
    }

    @Test("The menu shows the quit stage first and turns off every feature action")
    func quitInMenu() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        let before = MenuBarMenu.items(for: fixture.state) {}
        #expect(before.first?.title == "Open Jerd")
        #expect(actions(before).contains(where: { $0.id == "storage.stop" && $0.isEnabled }))

        _ = fixture.state.requestTermination { _ in }
        await waitUntil { fixture.state.shutdown.message == ShutdownPhase.storage.message }
        let items = MenuBarMenu.items(for: fixture.state) {}
        #expect(items.first?.id == "menu.activity")
        #expect(items.first?.title == "Stopping storage…")
        let featureIDs = Set(fixture.state.features.flatMap { actions($0.menuItems) }.map(\.id))
        #expect(!featureIDs.isEmpty)
        for action in actions(items) where featureIDs.contains(action.id) {
            #expect(!action.isEnabled, "\(action.id) stays enabled during the quit")
        }
        #expect(actions(items).first(where: { $0.id == "menu.quit" })?.isEnabled == true)
        #expect(actions(items).first(where: { $0.id == "menu.settings" })?.isEnabled == true)
    }

    @Test("Global feature work shows at the top of the menu")
    func featureWorkInMenu() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.sites.configure { $0.suspendsChanges = true }
        await fixture.state.launch()
        fixture.state.sites.startAll()
        let items = MenuBarMenu.items(for: fixture.state) {}
        #expect(items.first?.title == "Checking PHP-FPM and HTTPS…")
        await fixture.sites.configure { $0.suspendsChanges = false }
        await fixture.state.sites.stopAll()?.value
        #expect(actions(items).allSatisfy({ $0.id != "menu.activity" }))
    }

    @Test("During a quit every dashboard card action is off")
    func quitInCards() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        let storageActions = DashboardCards.summary(for: .storage, in: fixture.state).actions
        #expect(storageActions.contains { $0.isEnabled } == true)
        _ = fixture.state.requestTermination { _ in }
        await waitUntil { fixture.state.shutdown.message == ShutdownPhase.storage.message }
        for section in DashboardCards.sections {
            let summary = DashboardCards.summary(for: section, in: fixture.state)
            #expect(summary.actions.allSatisfy({ !$0.isEnabled }), "\(section.title) keeps an action on")
        }
    }
}

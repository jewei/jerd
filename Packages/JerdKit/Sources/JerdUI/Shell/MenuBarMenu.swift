import SwiftUI

/// Builds the menu bar menu from the feature summaries: open commands, each feature's
/// entries, the app commands, and Quit.
@MainActor
enum MenuBarMenu {
    static func items(for state: AppState, quit: @escaping @MainActor () -> Void) -> [MenuBarItem] {
        var items = openItems(for: state)
        for feature in state.features where !feature.menuItems.isEmpty {
            items.append(.divider(id: "divider.\(feature.section.title.lowercased())"))
            items += feature.menuItems
        }
        items.append(.divider(id: "divider.app"))
        items += appItems(for: state)
        items.append(.divider(id: "divider.quit"))
        items.append(
            .action(FeatureAction(id: "menu.quit", title: "Quit Jerd", perform: quit), shortcut: CommandShortcut("q", modifiers: .command)))
        return items
    }

    private static func openItems(for state: AppState) -> [MenuBarItem] {
        let openJerd = FeatureAction(id: "menu.open", title: "Open Jerd") { state.openMainWindow() }
        let sections = DashboardCards.sections.map { section in
            MenuBarItem.action(
                FeatureAction(id: "menu.open.\(section.title.lowercased())", title: "Open \(section.title)") {
                    state.open(.section(section))
                })
        }
        return [.action(openJerd)] + sections
    }

    private static func appItems(for state: AppState) -> [MenuBarItem] {
        [AppCommand.settings, .about, .checkForUpdates].map { command in
            MenuBarItem.action(
                FeatureAction(
                    id: "menu.\(command.identifier)", title: command.title(in: state),
                    isEnabled: command.isEnabled(in: state)
                ) {
                    command.perform(in: state)
                }, shortcut: command.shortcut)
        }
    }
}

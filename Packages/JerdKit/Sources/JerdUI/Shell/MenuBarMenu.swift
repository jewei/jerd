import SwiftUI

/// Builds the menu bar menu from the feature summaries: the running work, open commands, each
/// feature's entries, the app commands, and Quit. During a quit the first line shows the quit
/// stage and every feature entry is off, so the menu is useful when no window shows.
@MainActor
enum MenuBarMenu {
    static func items(for state: AppState, quit: @escaping @MainActor () -> Void) -> [MenuBarItem] {
        var items = activityItems(for: state) + openItems(for: state)
        for feature in state.features where !feature.menuItems.isEmpty {
            items.append(.divider(id: "divider.\(feature.section.title.lowercased())"))
            let entries = feature.menuItems
            items += state.isQuitting ? entries.map { $0.disablingActions() } : entries
        }
        items.append(.divider(id: "divider.app"))
        items += appItems(for: state)
        items.append(.divider(id: "divider.quit"))
        items.append(
            .action(
                FeatureAction(id: "menu.quit", title: "Quit Jerd", perform: quit),
                shortcut: CommandShortcut("q", modifiers: .command)))
        return items
    }

    /// The quit stage or the global work, as a disabled line at the top.
    private static func activityItems(for state: AppState) -> [MenuBarItem] {
        guard let activity = state.bannerActivity else { return [] }
        return [.text(activity.message, id: "menu.activity"), .divider(id: "divider.activity")]
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

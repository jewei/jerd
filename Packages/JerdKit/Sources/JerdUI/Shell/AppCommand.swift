import SwiftUI

/// One app menu or View menu command: its title, shortcut, enabled rule, and action. The
/// rules are values, so tests prove every command and shortcut without a menu.
public enum AppCommand: Hashable, Sendable {
    case about
    case checkForUpdates
    /// File › New (⌘N): the `newItemAction` of the current section, for example New Database….
    case newItem
    /// Settings… opens Appearance in the main window. There is no separate Settings window.
    case settings
    case toggleSidebar
    case showSection(AppSection)

    /// Every command, in menu order.
    public static let all: [AppCommand] =
        [.about, .checkForUpdates, .newItem, .settings, .toggleSidebar]
        + AppSection.allCases.map(AppCommand.showSection)

    /// A stable name for menu items and tests, for example `check-for-updates`.
    public var identifier: String {
        switch self {
        case .about: "about"
        case .checkForUpdates: "check-for-updates"
        case .newItem: "new-item"
        case .settings: "settings"
        case .toggleSidebar: "toggle-sidebar"
        case .showSection(let section): "section.\(section.title.lowercased())"
        }
    }

    @MainActor
    public func title(in state: AppState) -> String {
        switch self {
        case .about: "About Jerd"
        case .checkForUpdates: "Check for Updates…"
        case .newItem: state.newItemAction?.title ?? "New…"
        case .settings: "Settings…"
        case .toggleSidebar:
            state.navigation.isSidebarVisible(in: state.navigation.section) ? "Hide Sidebar" : "Show Sidebar"
        case .showSection(let section): section.title
        }
    }

    /// The key and modifiers, or nil for a command without a shortcut.
    public var shortcut: CommandShortcut? {
        switch self {
        case .about, .checkForUpdates: nil
        case .newItem: CommandShortcut("n", modifiers: .command)
        case .settings: CommandShortcut(",", modifiers: .command)
        case .toggleSidebar: CommandShortcut("s", modifiers: [.command, .control])
        case .showSection(let section): CommandShortcut(section.shortcutKey, modifiers: .command)
        }
    }

    @MainActor
    public func isEnabled(in state: AppState) -> Bool {
        switch self {
        case .about, .settings, .showSection: true
        case .checkForUpdates: state.appUpdates.canCheckForUpdates
        case .newItem: state.newItemAction?.isEnabled == true && !state.isQuitting
        case .toggleSidebar: state.navigation.canToggleSidebar
        }
    }

    @MainActor
    public func perform(in state: AppState) {
        switch self {
        case .about: state.open(.dashboard(.about))
        case .checkForUpdates: state.appUpdates.checkForUpdates()
        case .newItem:
            if isEnabled(in: state) { state.newItemAction?.perform() }
        case .settings: state.open(.dashboard(.appearance))
        case .toggleSidebar: state.navigation.toggleSidebar()
        case .showSection(let section): state.open(.section(section))
        }
    }
}

/// One entry of the menu bar menu. Features describe their entries as values, so the menu is
/// built by one view and tests can read the whole tree.
public struct MenuBarItem: Identifiable {
    /// The kind of entry.
    public enum Kind {
        case action(FeatureAction)
        /// A disabled line of text, for example a status.
        case text(String)
        case submenu(title: String, items: [MenuBarItem])
        case divider
    }

    public let id: String
    public let kind: Kind
    /// The key equivalent of an action, for example ⌘, for Settings….
    public let shortcut: CommandShortcut?

    public init(id: String, kind: Kind, shortcut: CommandShortcut? = nil) {
        self.id = id
        self.kind = kind
        self.shortcut = shortcut
    }

    public static func action(_ action: FeatureAction, shortcut: CommandShortcut? = nil) -> MenuBarItem {
        MenuBarItem(id: action.id, kind: .action(action), shortcut: shortcut)
    }

    public static func text(_ text: String, id: String) -> MenuBarItem {
        MenuBarItem(id: id, kind: .text(text))
    }

    public static func submenu(_ title: String, id: String, items: [MenuBarItem]) -> MenuBarItem {
        MenuBarItem(id: id, kind: .submenu(title: title, items: items))
    }

    public static func divider(id: String) -> MenuBarItem {
        MenuBarItem(id: id, kind: .divider)
    }

    /// The same entry with every action off, also inside submenus.
    public func disablingActions() -> MenuBarItem {
        switch kind {
        case .action(let action):
            MenuBarItem(id: id, kind: .action(action.disabled()), shortcut: shortcut)
        case .submenu(let title, let items):
            MenuBarItem(id: id, kind: .submenu(title: title, items: items.map { $0.disablingActions() }))
        case .text, .divider:
            self
        }
    }

    /// The visible title, or nil for a divider.
    public var title: String? {
        switch kind {
        case .action(let action): action.title
        case .text(let text): text
        case .submenu(let title, _): title
        case .divider: nil
        }
    }
}

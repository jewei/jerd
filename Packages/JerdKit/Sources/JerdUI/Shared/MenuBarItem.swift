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

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public static func action(_ action: FeatureAction) -> MenuBarItem {
        MenuBarItem(id: action.id, kind: .action(action))
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

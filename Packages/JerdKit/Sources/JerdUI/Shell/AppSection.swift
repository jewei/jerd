import JerdDesign
import SwiftUI

/// A top-level section of the main window. The case order is the order of the section picker
/// and of the ⌘1…⌘5 shortcuts, and it must not change.
public enum AppSection: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case dashboard
    case sites
    case databases
    case storage
    case mail

    public var id: Int { rawValue }

    /// The name in the section picker, the View menu, and the menu bar.
    public var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .sites: "Sites"
        case .databases: "Databases"
        case .storage: "Storage"
        case .mail: "Mail"
        }
    }

    /// The symbol of the area, for dashboard cards and menus.
    public var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .sites: "globe"
        case .databases: "cylinder.split.1x2"
        case .storage: "externaldrive.badge.icloud"
        case .mail: "envelope"
        }
    }

    /// The tint of the area's icon tile.
    public var tint: ServiceTint {
        switch self {
        case .dashboard: .neutral
        case .sites: .sites
        case .databases: .databases
        case .storage: .storage
        case .mail: .mail
        }
    }

    /// Mail is one page, so it has no sidebar.
    public var hasSidebar: Bool { self != .mail }

    /// The key of the section shortcut: ⌘1 for Dashboard through ⌘5 for Mail.
    public var shortcutKey: Character {
        Character(String(rawValue + 1))
    }
}

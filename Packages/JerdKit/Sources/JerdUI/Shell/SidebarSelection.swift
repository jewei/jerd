import Foundation

/// The item that a feature sidebar selects. Each case belongs to exactly one section.
public enum SidebarSelection: Hashable, Sendable {
    case site(UUID)
    case tunnel(UUID)
    case database(UUID)
    case bucket(String)

    /// The section whose sidebar shows this item.
    public var section: AppSection {
        switch self {
        case .site, .tunnel: .sites
        case .database: .databases
        case .bucket: .storage
        }
    }
}

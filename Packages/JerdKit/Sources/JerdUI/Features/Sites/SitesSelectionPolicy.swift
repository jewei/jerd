import Foundation

/// Which item the Sites page shows. A selection of an item that no longer exists, or no
/// selection, falls back to the first site, then the first tunnel, so the page never shows a
/// removed item and needs no clean-up after a removal.
public enum SitesSelectionPolicy {
    public static func resolve(
        _ selection: SidebarSelection?, siteIDs: [UUID], tunnelIDs: [UUID]
    ) -> SidebarSelection? {
        switch selection {
        case .site(let id) where siteIDs.contains(id): return selection
        case .tunnel(let id) where tunnelIDs.contains(id): return selection
        default: break
        }
        if let first = siteIDs.first { return .site(first) }
        return tunnelIDs.first.map(SidebarSelection.tunnel)
    }
}

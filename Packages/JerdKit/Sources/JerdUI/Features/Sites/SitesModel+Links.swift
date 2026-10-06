import Foundation
import JerdWeb

extension SitesModel {
    /// The item that the Sites page shows for the user's choice. A failed load shows its own
    /// page with Retry Load, unless the user chose an item.
    public func shownItem(for chosen: SidebarSelection?) -> SidebarSelection? {
        if !isLoaded, operation.failureMessage != nil, chosen == nil { return nil }
        return SitesSelectionPolicy.resolve(
            chosen, siteIDs: sites.map(\.id), tunnelIDs: tunnels.registrations.map(\.id))
    }

    /// `https://<hostname>` of a site.
    public static func address(of site: Site) -> URL? {
        URL(string: "https://\(site.hostname)")
    }

    /// Opens a served site in the default browser.
    public func openInBrowser(_ site: Site) {
        guard let url = Self.address(of: site) else { return }
        workspace.open(url)
    }

    /// Shows the project folder in Finder.
    public func revealProject(_ site: Site) {
        workspace.reveal(URL(fileURLWithPath: site.projectPath, isDirectory: true))
    }

    /// Shows the document root in Finder.
    public func revealDocumentRoot(_ site: Site) {
        workspace.reveal(URL(fileURLWithPath: site.documentRoot, isDirectory: true))
    }

    /// Copies the site address. The toast shows in the window from any page or menu.
    public func copyAddress(_ site: Site) {
        clipboard.copy("https://\(site.hostname)", confirmation: "Copied site URL")
    }

    /// Opens the folder of the web logs, or says that none exists yet.
    public func openLogs() {
        Task {
            guard let url = await port.environmentLogs() else {
                if !operation.isWorking {
                    operation = .failed(message: "The web environment log is not available yet.")
                }
                return
            }
            workspace.open(url)
        }
    }
}

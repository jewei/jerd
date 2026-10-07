import JerdDesign
import JerdWeb
import SwiftUI

/// The Sites sidebar: the registered sites, then the tunnels, and the Add footer.
struct SitesSidebar: View {
    let state: AppState
    let model: SitesModel

    var body: some View {
        List(selection: selection) {
            Section("Your Projects") {
                ForEach(model.sites) { site in
                    SiteSidebarRow(model: model, site: site)
                        .tag(SidebarSelection.site(site.id))
                }
                if model.sites.isEmpty {
                    SidebarPlaceholder(sitePlaceholder)
                }
            }
            Section("Tunnels") {
                ForEach(model.tunnels.registrations) { tunnel in
                    TunnelSidebarRow(model: model.tunnels, tunnel: tunnel)
                        .tag(SidebarSelection.tunnel(tunnel.id))
                }
                if model.tunnels.registrations.isEmpty {
                    SidebarPlaceholder(tunnelPlaceholder)
                }
            }
        }
        .listStyle(.sidebar)
        .sidebarFooter {
            SitesSidebarFooter(model: model)
        }
    }

    private var sitePlaceholder: String {
        if model.isLoaded { return "No sites added" }
        return model.operation.failureMessage == nil ? "Loading sites…" : "Site settings could not be loaded"
    }

    private var tunnelPlaceholder: String {
        if model.tunnels.loadFailure != nil { return "Tunnel settings could not be loaded" }
        return model.tunnels.isLoaded ? "No tunnels added" : "Loading tunnels…"
    }

    /// The shell's selection, shown with the same fallback as the page: the first site when
    /// nothing is chosen.
    private var selection: Binding<SidebarSelection?> {
        let chosen = state.sidebarSelection(in: .sites)
        return Binding {
            model.shownItem(for: chosen.wrappedValue)
        } set: { selection in
            chosen.wrappedValue = selection
        }
    }
}

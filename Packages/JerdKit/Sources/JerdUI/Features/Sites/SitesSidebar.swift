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
                    placeholder(sitePlaceholder)
                }
            }
            Section("Tunnels") {
                ForEach(model.tunnels.registrations) { tunnel in
                    TunnelSidebarRow(model: model.tunnels, tunnel: tunnel)
                        .tag(SidebarSelection.tunnel(tunnel.id))
                }
                if model.tunnels.registrations.isEmpty {
                    placeholder(tunnelPlaceholder)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
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

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .textRole(.detail)
            .padding(.vertical, Spacing.tight)
            .selectionDisabled()
    }

    /// The shown item. A native list refresh can report nil; that never clears the selection.
    private var selection: Binding<SidebarSelection?> {
        Binding {
            model.shownItem(for: state.navigation.selection(in: .sites))
        } set: { selection in
            state.navigation.select(selection)
        }
    }
}

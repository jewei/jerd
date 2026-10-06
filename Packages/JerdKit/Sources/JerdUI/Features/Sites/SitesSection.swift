import JerdDesign
import SwiftUI

/// The detail of the Sites section: the selected site or tunnel, or the empty state, with the
/// sheets and confirmations of both models.
struct SitesSection: View {
    let state: AppState
    @Bindable var model: SitesModel

    var body: some View {
        content
            .background(addShortcut)
            .sheet(item: $model.sheet) { sheet in
                switch sheet {
                case .editor(let editor): SiteEditorSheet(model: model, editor: editor)
                case .approval(let approval): HTTPSApprovalSheet(model: model, approval: approval)
                }
            }
            .sitesConfirmation(model)
            .tunnelSheets(model.tunnels)
            .tunnelConfirmation(model.tunnels)
    }

    @ViewBuilder private var content: some View {
        switch resolvedSelection {
        case .site(let id):
            if let site = model.site(id) {
                SiteDetailPage(state: state, model: model, site: site).id(id)
            }
        case .tunnel(let id):
            if let tunnel = model.tunnels.registration(id) {
                TunnelDetailPage(state: state, sites: model, tunnel: tunnel).id(id)
            }
        default:
            SitesEmptyState(model: model)
        }
    }

    private var resolvedSelection: SidebarSelection? {
        SitesSelectionPolicy.resolve(
            state.navigation.selection(in: .sites), siteIDs: model.sites.map(\.id),
            tunnelIDs: model.tunnels.registrations.map(\.id))
    }

    /// ⌘N adds a site while the Sites page shows. A hidden page is disabled, so the shortcut
    /// works only here.
    private var addShortcut: some View {
        Button("Add Site…") { model.beginAdd() }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!model.canChange)
            .opacity(0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

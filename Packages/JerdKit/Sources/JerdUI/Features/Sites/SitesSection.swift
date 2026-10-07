import JerdDesign
import SwiftUI

/// The detail of the Sites section: the selected site or tunnel, or the empty state, with the
/// sheets and confirmations of both models.
struct SitesSection: View {
    let state: AppState
    let model: SitesModel

    var body: some View {
        content
            .sheet(item: SheetBinding.item({ model.sheet }, dismiss: model.dismissSheet)) { sheet in
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
        model.shownItem(for: state.navigation.selection(in: .sites))
    }
}

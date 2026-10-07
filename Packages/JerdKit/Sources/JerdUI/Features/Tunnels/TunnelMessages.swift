import JerdDesign
import JerdTunnels
import SwiftUI

/// The banners of a tunnel page. Each message shows once, with a title: the failed operation,
/// the reason of a failed connector, a failed connect at launch, a connector that did not
/// stop, and saved settings that need an edit. Only one banner carries Edit Tunnel….
struct TunnelMessages: View {
    let model: TunnelsModel
    @Environment(\.isQuitting) private var isQuitting
    let sites: SitesModel
    let tunnel: TunnelRegistration

    var body: some View {
        OperationFailureBanner(operation: model.operation, identifier: "tunnel.error") { model.dismissFailure() }
        ForEach(model.banners(for: tunnel.id), id: \.message) { banner in
            InlineMessage(
                banner.message, kind: .error, title: banner.title, style: .banner,
                action: banner.offersEdit ? editAction : nil, identifier: "tunnel.state-error")
        }
        if let issue = model.snapshots[tunnel.id]?.settingsIssue {
            InlineMessage(
                issue, kind: .warning, title: "These settings need an edit", style: .banner, action: editAction,
                identifier: "tunnel.settings-issue")
        }
    }

    private var editAction: PageAction {
        PageAction(
            "Edit Tunnel…", isEnabled: model.canChange && !isQuitting && !model.isActive(tunnel.id),
            identifier: "tunnel.banner-edit"
        ) {
            model.beginEdit(tunnel, sites: sites.sites)
        }
    }
}

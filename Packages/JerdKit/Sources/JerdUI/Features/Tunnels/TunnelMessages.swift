import JerdDesign
import JerdTunnels
import SwiftUI

/// The banners of a tunnel page. Each message shows once, with a title: the failed operation,
/// the reason of a failed connector, a failed connect at launch, a connector that did not
/// stop, saved settings that need an edit, and a public hostname without a DNS record. Only one
/// banner carries Edit Tunnel….
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
        if let warning = model.hostnameWarnings[tunnel.id] {
            InlineMessage(
                warning, kind: .warning, title: "The public hostname has no DNS record", style: .banner,
                action: PageAction("Check Again", identifier: "tunnel.hostname-check") {
                    model.checkHostnameAgain(tunnel.id)
                }, identifier: "tunnel.hostname-missing")
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

import JerdDesign
import JerdTunnels
import SwiftUI

/// The banners of a tunnel page. Each message shows once: the failed operation, the reason
/// of a failed connector, a failed connect at launch, and saved settings that need an edit.
struct TunnelMessages: View {
    let model: TunnelsModel
    let sites: SitesModel
    let tunnel: TunnelRegistration

    var body: some View {
        OperationFailureBanner(operation: model.operation, identifier: "tunnel.error") { model.dismissFailure() }
        ForEach(messages, id: \.self) { message in
            InlineMessage(message, kind: .error, style: .banner, identifier: "tunnel.state-error")
        }
        if let issue = model.snapshots[tunnel.id]?.settingsIssue {
            InlineMessage(
                issue, kind: .warning, title: "These settings need an edit", style: .banner,
                action: PageAction("Edit Tunnel…", isEnabled: model.canChange && !model.isActive(tunnel.id)) {
                    model.beginEdit(tunnel, sites: sites.sites)
                }, identifier: "tunnel.settings-issue")
        }
    }

    /// The connector failure and the launch failure, without the operation failure again.
    private var messages: [String] {
        let candidates = [model.state(of: tunnel.id).failureMessage, model.startupFailures[tunnel.id]]
        var shown: [String] = []
        for case let message? in candidates where message != model.operation.failureMessage && !shown.contains(message)
        {
            shown.append(message)
        }
        return shown
    }
}

import JerdDesign
import SwiftUI

/// The HTTPS approval: the hostnames, what changes on this Mac, the trust scope, and the CA
/// fingerprint. Cancel is always enabled; it closes the sheet and never cuts a macOS prompt.
struct HTTPSApprovalSheet: View {
    let model: SitesModel
    let approval: HTTPSApproval

    var body: some View {
        SheetScaffold(
            approval.title, message: "macOS can ask for administrator approval.", size: .wide,
            confirmation: SheetConfirmation(
                "Approve and Start", isEnabled: model.canChange, identifier: "https-approval"
            ) {
                model.approve(approval)
            },
            workingMessage: model.operation.workingMessage, cancel: model.cancelApproval
        ) {
            Section("Hostnames") {
                ForEach(approval.hostnames, id: \.self) { hostname in
                    Text(hostname).font(TextRole.code.font).textSelection(.enabled)
                }
            }
            if !approval.removedHostnames.isEmpty {
                Section("Setup Removed For") {
                    ForEach(approval.removedHostnames, id: \.self) { hostname in
                        Text(hostname).font(TextRole.code.font).textSelection(.enabled)
                    }
                }
            }
            HTTPSApprovalChangesSection()
            Section {
                ValueRow("CA SHA-256", value: approval.fingerprint, isCode: true)
                ActionRow("Helper approval", detail: "Allow the Jerd helper if macOS asks for it.") {
                    Button("Open Login Items & Extensions") { model.openLoginItems() }
                }
            } footer: {
                FormFooter("Use Remove System Setup to remove these host entries and the certificate later.")
            }
            if let failure = model.approvalFailure {
                InlineMessage(failure, kind: .error, identifier: "https-approval.error")
            }
        }
    }
}

import JerdDesign
import SwiftUI

/// The HTTPS approval: a failure first, then the scope of the CA trust as a warning, the
/// hostnames, the CA fingerprint that the user compares in the macOS prompt, and what changes
/// on this Mac. The failure, the warning, and the fingerprint are visible without scrolling. Cancel is always
/// enabled; it closes the sheet and never cuts a macOS prompt or a running approval.
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
            workingMessage: model.operation.workingMessage, cancel: model.closeApproval
        ) {
            SheetTopMessage(message: model.approvalFailure, kind: .error, identifier: "https-approval.error")
            SheetTopMessage(
                message: HTTPSApprovalChangesSection.trustWarning, kind: .warning, identifier: "https-approval.trust")
            Section {
                ApprovalValueRow(label: "Hostnames", value: approval.hostnames.joined(separator: ", "))
                if !approval.removedHostnames.isEmpty {
                    ApprovalValueRow(
                        label: "Setup removed for", value: approval.removedHostnames.joined(separator: ", "))
                }
                ApprovalValueRow(label: "CA SHA-256", value: approval.fingerprint)
                ActionRow("Helper approval", detail: "Allow the Jerd helper if macOS asks for it.") {
                    Button("Open Login Items & Extensions") { model.openLoginItems() }
                }
            } footer: {
                FormFooter("Use Remove System Setup to remove these host entries and the certificate later.")
            }
            HTTPSApprovalChangesSection()
        }
    }
}

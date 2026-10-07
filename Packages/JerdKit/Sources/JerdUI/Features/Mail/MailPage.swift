import JerdDesign
import SwiftUI

/// The Mail section: one page with the inbox status, its connection, the Laravel settings,
/// a test email, its files, and its ports. Mail has no sidebar. Before Mailpit is installed it
/// shows the pinned Mailpit first, and it owns the install confirmation.
struct MailPage: View {
    let model: MailModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        let actions = MailHeaderActions(model: model, isQuitting: isQuitting)
        FormPage {
            PageHeader(
                "Mail", subtitle: "A local inbox for your application's test emails.",
                status: NamedStatus("Mail status", model.status), primaryAction: actions.primary,
                secondaryActions: actions.secondary
            ) {
                if model.operation.isWorking {
                    BusyIndicator(model.operation.workingMessage ?? "Working…")
                }
            }
        } messages: {
            MailPageMessages(model: model)
        } content: {
            if model.loadState.isLoaded, !model.hasRuntime,
                model.runtimeOffer != nil || model.runtimeInstallation != nil
            {
                ServiceRuntimeSection(model: model)
            }
            MailConnectionSection(model: model)
            MailInboxSection(model: model)
            ServiceFilesSection(
                files: model.files,
                copy: .init(
                    dataLabel: "Inbox data", logSubject: "mail log",
                    missingData: "Start the mail service once to create its inbox.",
                    missingLog: "The mail log is not available yet.",
                    footer: "Messages remain in the inbox after Stop or Quit."),
                reveal: model.revealInbox, openLog: model.openLog)
            MailServiceSection(model: model)
        }
        .sheet(isPresented: SheetBinding.isPresented({ model.portsDraft != nil }, dismiss: model.cancelPorts)) {
            MailPortsSheet(model: model)
        }
        .serviceRuntimeConfirmation(
            .mail, request: model.pendingRuntimeInstall, confirm: { model.confirmRuntimeInstall() },
            dismiss: { model.pendingRuntimeInstall = nil })
    }
}

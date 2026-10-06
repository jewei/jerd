import JerdDesign
import SwiftUI

/// The Mail section: one page with the inbox status, its connection, the Laravel settings,
/// a test email, its files, and its ports. Mail has no sidebar.
struct MailPage: View {
    @Bindable var model: MailModel

    var body: some View {
        FormPage {
            PageHeader(
                "Mail", subtitle: "A local inbox for your application's test emails.",
                status: NamedStatus("Mail status", model.status), primaryAction: primaryAction,
                secondaryActions: secondaryActions
            ) {
                if model.operation.isWorking {
                    BusyIndicator(model.operation.workingMessage ?? "Working…")
                }
            }
        } messages: {
            MailPageMessages(model: model)
        } content: {
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
        .sheet(isPresented: isEditingPorts) {
            MailPortsSheet(model: model)
        }
    }

    /// The next step: Start when stopped, Open Inbox when running, Stop to retry a stop.
    private var primaryAction: PageAction? {
        if model.state.isRunning { return inboxAction }
        if model.state.offersStop { return stopAction }
        return PageAction(
            "Start Mail", systemImage: "play.fill", isEnabled: model.canStart, identifier: "mail.start"
        ) { model.start() }
    }

    private var secondaryActions: [PageAction] {
        model.state.isRunning ? [stopAction] : []
    }

    private var stopAction: PageAction {
        PageAction("Stop Mail", systemImage: "stop.fill", isEnabled: model.canStop, identifier: "mail.stop") {
            model.stop()
        }
    }

    private var inboxAction: PageAction {
        PageAction(
            "Open Inbox", systemImage: "tray", isEnabled: model.canOpenInbox, identifier: "mail.open-inbox"
        ) { model.openInbox() }
    }

    private var isEditingPorts: Binding<Bool> {
        Binding {
            model.portsDraft != nil
        } set: { isPresented in
            if !isPresented { model.cancelPorts() }
        }
    }
}

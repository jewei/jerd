import JerdDesign
import SwiftUI

/// The test email and its result.
struct MailInboxSection: View {
    let model: MailModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        Section {
            ActionRow("Test email", detail: "Send a sample message to the local inbox.") {
                Button("Send Test Email", systemImage: "paperplane", action: { model.sendTestEmail() })
                    .disabled(isQuitting || !model.canSendTestEmail)
                    .help(model.state.isRunning ? "Send Test Email" : "Start mail to send a test email.")
                    .accessibilityIdentifier("mail.send-test")
            }
            if let result = model.testResult {
                InlineMessage(result, kind: .success, identifier: "mail.test-result")
            }
        } header: {
            Text("Inbox")
        } footer: {
            FormFooter("Open the inbox to search messages and inspect their HTML and attachments.")
        }
    }
}

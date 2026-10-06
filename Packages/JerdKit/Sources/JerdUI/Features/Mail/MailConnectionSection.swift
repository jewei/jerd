import JerdDesign
import SwiftUI

/// How an application reaches the inbox, and the Laravel settings to copy.
struct MailConnectionSection: View {
    let model: MailModel

    var body: some View {
        Section {
            ValueRow("Host", value: "127.0.0.1", isCode: true)
            ValueRow("SMTP port", value: String(model.settings.smtpPort), isCode: true, copy: model.copySMTPPort)
            ValueRow(
                "Inbox URL", value: model.settings.inboxURL.absoluteString, isCode: true, copy: model.copyInboxURL)
            ValueRow("Authentication", value: "No username or password")
            ValueRow("Encryption", value: "None · Local SMTP and HTTP")
        } header: {
            Text("Connection")
        } footer: {
            FormFooter(
                "Available only on this Mac. Messages are captured here; they are not sent to external recipients.")
        }
        Section {
            ActionRow(".env settings", detail: "MAIL_HOST and MAIL_PORT for this inbox, without a password.") {
                Button("Copy Laravel Settings", action: model.copyEnvironment)
                    .disabled(!model.hasRuntime)
                    .accessibilityIdentifier("mail.copy-laravel")
            }
        } header: {
            Text("Laravel")
        } footer: {
            FormFooter("Paste these settings into your application's .env file, then clear any cached configuration.")
        }
    }
}

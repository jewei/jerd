import JerdDesign
import SwiftUI

/// How an application reaches the inbox, and the Laravel settings to copy. Before Mailpit is
/// installed there is no address yet: the registration chooses the ports.
struct MailConnectionSection: View {
    let model: MailModel

    var body: some View {
        Section {
            ForEach(Self.values(model)) { ConnectionValueRow(value: $0) }
        } header: {
            Text("Connection")
        } footer: {
            FormFooter(
                model.hasRuntime
                    ? "Available only on this Mac. Messages are captured here; they are not sent to external recipients."
                    : ServiceRuntimeCopy.mail.portsNotChosen)
        }
        Section {
            ActionRow(".env settings", detail: "MAIL_HOST and MAIL_PORT for this inbox, without a password.") {
                CopyLaravelSettingsButton(
                    isEnabled: model.canCopyEnvironment, identifier: "mail.copy-laravel", perform: model.copyEnvironment
                )
            }
        } header: {
            Text("Laravel")
        } footer: {
            FormFooter("Paste these settings into your application's .env file, then clear any cached configuration.")
        }
    }

    /// The host, ports, and URL to paste; the authentication and encryption to read.
    static func values(_ model: MailModel) -> [ConnectionValue] {
        let host = "127.0.0.1"
        guard model.hasRuntime else {
            return [
                .description("SMTP server", "Not chosen yet"), .description("Inbox URL", "Not chosen yet"),
                .description("Authentication", "No username or password"),
                .description("Encryption", "None · Local SMTP and HTTP"),
            ]
        }
        return [
            .pasteable("Host", host) { model.copyValue(host, label: "Host") },
            .pasteable("SMTP port", String(model.settings.smtpPort), copy: model.copySMTPPort),
            .pasteable("Inbox URL", model.settings.inboxURL.absoluteString, copy: model.copyInboxURL),
            .description("Authentication", "No username or password"),
            .description("Encryption", "None · Local SMTP and HTTP"),
        ]
    }
}

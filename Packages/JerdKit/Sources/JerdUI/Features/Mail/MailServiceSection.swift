import JerdDesign
import SwiftUI

/// The Mailpit version and the two ports, with Edit Ports… while the inbox is stopped.
struct MailServiceSection: View {
    let model: MailModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        Section {
            ValueRow("Mailpit", value: model.settings.runtime.map { "Version \($0.version)" } ?? "Not installed")
            ActionRow("Ports", detail: portsDetail) {
                Button("Edit Ports…", action: model.editPorts)
                    .disabled(isQuitting || !model.canEditPorts)
                    .accessibilityLabel("Edit mail ports")
                    .accessibilityIdentifier("mail.edit-ports")
            }
        } header: {
            Text("Service")
        } footer: {
            FormFooter(
                !model.hasRuntime
                    ? ServiceRuntimeCopy.mail.portsNotChosen
                    : model.state.offersStop
                        ? "Stop mail to change its ports." : "Changing ports keeps every message in the inbox.")
        }
    }

    /// The two ports, or why there are none yet: the Mailpit registration chooses them.
    private var portsDetail: String {
        model.hasRuntime ? "SMTP \(model.settings.smtpPort) · Web \(model.settings.webPort)" : "Not chosen yet"
    }
}

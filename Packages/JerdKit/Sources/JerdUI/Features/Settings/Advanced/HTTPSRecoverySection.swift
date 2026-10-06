import JerdDesign
import JerdSystem
import SwiftUI

/// The interrupted HTTPS setup that the helper reports, and its two recovery steps.
struct HTTPSRecoverySection: View {
    let model: AdvancedModel
    let status: SystemRecoveryStatus

    var body: some View {
        Section {
            InlineMessage(
                status.details.joined(separator: " "), kind: .warning, title: "\(status.operation) · \(status.phase)",
                identifier: "advanced.https-recovery")
            ValueRow("CA SHA-256", value: status.fingerprint ?? "Unavailable", isCode: true)
            ActionRow("Recovery", detail: "Choose how Jerd ends the interrupted setup.") {
                Button("Restore Previous Setup…") {
                    model.confirmation = .restoreHTTPS(status)
                }
                .disabled(!status.canRestore || !model.isIdle)
                .accessibilityIdentifier("advanced.https-restore")
                Button("Remove Tracked Setup…", role: .destructive) {
                    model.confirmation = .removeHTTPS(status)
                }
                .disabled(!status.canRemove || !model.isIdle)
                .accessibilityIdentifier("advanced.https-remove")
            }
        } header: {
            Text("Interrupted HTTPS Setup")
        } footer: {
            FormFooter("Sites cannot start until this setup is recovered.")
        }
    }
}

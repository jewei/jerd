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
            fingerprintRow
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

    /// The fingerprint under its label, at the same inset: a SHA-256 value does not fit beside
    /// the label at the compact width, and a wrapped value would start at another inset.
    private var fingerprintRow: some View {
        let fingerprint = status.fingerprint ?? "Unavailable"
        return VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text("CA SHA-256")
            Text(fingerprint)
                .font(TextRole.code.font)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("advanced.https-fingerprint")
    }
}

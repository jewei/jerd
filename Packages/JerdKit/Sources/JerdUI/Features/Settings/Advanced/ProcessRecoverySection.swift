import JerdDesign
import JerdProcess
import SwiftUI

/// Services that a previous Jerd session left, with Recover or Clear for each.
struct ProcessRecoverySection: View {
    let model: AdvancedModel

    var body: some View {
        Section {
            if model.findings.isEmpty {
                EmptySectionRow(
                    title: "No saved services",
                    detail: model.hasInspected
                        ? "Jerd found no services left by a previous session."
                        : "Select Inspect Recovery and Backups to check for a previous session.",
                    systemImage: "arrow.counterclockwise")
            }
            ForEach(model.findings) { finding in
                ActionRow(finding.title, detail: finding.detail) {
                    let title = finding.state == .stale ? "Clear Stale Record…" : "Recover Service…"
                    Button(title) {
                        model.confirmation = .forFinding(finding)
                    }
                    .disabled(!finding.canRecover || !model.isIdle)
                    .accessibilityLabel(
                        finding.state == .stale ? "Clear stale record for \(finding.title)" : "Recover \(finding.title)"
                    )
                    .accessibilityIdentifier(AccessibilityIdentifier.make("advanced", "recover", finding.id))
                }
            }
        } header: {
            Text("Process Recovery")
        } footer: {
            FormFooter(
                "Inspect services left by a previous Jerd session. Recovery uses a verified process identity and requests a graceful stop."
            )
        }
    }
}

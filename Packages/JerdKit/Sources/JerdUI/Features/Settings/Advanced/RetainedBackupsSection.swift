import JerdDesign
import JerdServiceKit
import SwiftUI

/// Mail and storage data copies that runtime updates kept, with Show and Delete for each.
struct RetainedBackupsSection: View {
    let model: AdvancedModel

    var body: some View {
        Section {
            if model.backups.isEmpty {
                EmptySectionRow(
                    title: "No retained backups",
                    detail: model.hasInspected
                        ? "Runtime updates kept no data copies."
                        : "Select Inspect Recovery and Backups to check for saved copies.",
                    systemImage: "archivebox")
            }
            ForEach(model.backups) { backup in
                backupRow(backup)
            }
        } header: {
            Text("Retained Runtime Backups")
        } footer: {
            FormFooter(
                "Runtime updates keep a copy of mail or storage data. Pending recovery protects these copies from deletion."
            )
        }
    }

    private func backupRow(_ backup: RetainedBackup) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            ActionRow("\(backup.service) · \(sizeText(backup))", detail: backup.detail) {
                Button("Delete Backup…", role: .destructive) {
                    model.confirmation = .deleteBackup(backup)
                }
                .disabled(backup.isProtected || !model.isIdle)
                .help(backup.isProtected ? "Pending recovery protects this backup." : "Delete Backup")
                .accessibilityLabel("Delete \(backup.service) backup")
                .accessibilityIdentifier(AccessibilityIdentifier.make("advanced", "delete-backup", backup.id))
            }
            PathRow("Backup folder", path: backup.directory.path) {
                model.reveal(backup)
            }
        }
    }

    private func sizeText(_ backup: RetainedBackup) -> String {
        backup.bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Size unavailable"
    }
}

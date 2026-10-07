import JerdDesign
import JerdRuntimes
import SwiftUI

/// The progress of an on-demand runtime installation on a service page: the step, a bar while the
/// length is known, and Cancel where the page owns the installation (a sheet cancels with its own
/// button). The Databases and Storage pages share it.
struct RuntimeInstallProgressRow: View {
    let message: String
    let progress: RuntimeInstallProgress?
    /// The runtime name for VoiceOver, for example `MySQL` or `RustFS`.
    let name: String
    /// The stable identifier of Cancel, for example `databases.mysql.cancel-install`.
    let cancelIdentifier: String
    let cancel: (@MainActor () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                if progress?.fraction == nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(message)
                    .textRole(.detail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let cancel {
                    Button("Cancel", action: cancel)
                        .fixedSize()
                        .accessibilityLabel("Cancel \(name) installation")
                        .accessibilityIdentifier(cancelIdentifier)
                }
            }
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
                    .accessibilityLabel(message)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension RuntimeInstallProgressRow {
    /// The row of a database engine installation.
    init(_ installation: DatabaseRuntimeInstallation, cancel: (@MainActor () -> Void)?) {
        self.init(
            message: installation.message, progress: installation.progress, name: installation.engine.title,
            cancelIdentifier: AccessibilityIdentifier.make("databases", installation.engine.rawValue, "cancel-install"),
            cancel: cancel)
    }

    /// The row of the RustFS installation.
    init(_ installation: StorageRuntimeInstallation, cancel: (@MainActor () -> Void)?) {
        self.init(
            message: installation.message, progress: installation.progress, name: "RustFS",
            cancelIdentifier: "storage.cancel-install", cancel: cancel)
    }
}

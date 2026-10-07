import JerdDesign
import SwiftUI

/// The progress of a database runtime installation: the step, a bar while the length is known,
/// and Cancel where the page owns the installation (the Add sheet cancels with its own button).
struct DatabaseRuntimeProgressRow: View {
    let installation: DatabaseRuntimeInstallation
    let cancel: (@MainActor () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                if installation.progress?.fraction == nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(installation.message)
                    .textRole(.detail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let cancel {
                    Button("Cancel", action: cancel)
                        .fixedSize()
                        .accessibilityLabel("Cancel \(installation.engine.title) installation")
                        .accessibilityIdentifier(
                            AccessibilityIdentifier.make("databases", installation.engine.rawValue, "cancel-install"))
                }
            }
            if let fraction = installation.progress?.fraction {
                ProgressView(value: fraction)
                    .accessibilityLabel(installation.message)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

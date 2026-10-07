import JerdDesign
import SwiftUI

/// The progress of the running installation, with Cancel until activation starts.
struct RuntimeProgressRow: View {
    let model: RuntimesModel
    let installation: RuntimeInstallation

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                if installation.progress?.fraction == nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(message)
                    .textRole(.detail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if installation.canCancel {
                    Button("Cancel") { model.cancelInstall() }
                        .accessibilityLabel("Cancel \(installation.kind.title) installation")
                        .accessibilityIdentifier(
                            AccessibilityIdentifier.make("runtimes", installation.kind.rawValue, "cancel"))
                }
            }
            if let fraction = installation.progress?.fraction {
                ProgressView(value: fraction)
                    .accessibilityLabel(message)
            }
        }
        .padding(.vertical, Spacing.tight)
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        installation.progress?.message ?? RuntimeCopy.startingMessage(installation.kind)
    }
}

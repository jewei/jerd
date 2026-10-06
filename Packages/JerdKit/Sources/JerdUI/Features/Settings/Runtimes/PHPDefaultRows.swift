import JerdDesign
import SwiftUI

/// One row per registered PHP runtime, with the default mark or a Use as Default button.
struct PHPDefaultRows: View {
    let model: RuntimesModel

    var body: some View {
        ForEach(model.registeredPHP) { php in
            ActionRow("PHP \(php.version)", detail: php.buildDigest.map { "Build \($0.prefix(12))" }) {
                if model.defaultPHPID == php.id {
                    Label("Default", systemImage: "checkmark.circle.fill")
                        .font(TextRole.detail.font.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("PHP \(php.version) is the default")
                } else {
                    Button("Use as Default") {
                        model.useAsDefault(php)
                    }
                    .disabled(!model.canChangeRuntimes)
                    .accessibilityLabel("Use PHP \(php.version) as default")
                    .accessibilityIdentifier(AccessibilityIdentifier.make("runtimes", "default", php.version))
                }
            }
        }
    }
}

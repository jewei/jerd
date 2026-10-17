import JerdDesign
import JerdWeb
import SwiftUI

/// The registered PHP runtimes, each with its paths and extensions, and Remove.
struct PHPRegistrationsSection: View {
    let model: AdvancedModel

    var body: some View {
        Section {
            if model.registrations.php.isEmpty {
                EmptySectionRow(
                    title: "No PHP runtimes registered",
                    detail: "Install a version in Runtimes, or select local executables above.",
                    systemImage: "shippingbox")
            }
            ForEach(model.registrations.php) { runtime in
                DisclosureGroup {
                    details(runtime)
                } label: {
                    label(runtime)
                }
                .accessibilityIdentifier(AccessibilityIdentifier.make("advanced", "php", runtime.id.uuidString))
            }
        } header: {
            Text("Registered PHP Runtimes")
        }
    }

    private func label(_ runtime: DevelopmentRuntime) -> some View {
        HStack(spacing: Spacing.small) {
            Text("PHP \(runtime.version)")
            // The ID tells two registrations of one version apart. It is not a build ID.
            Text("Registration \(runtime.id.uuidString.prefix(6))")
                .textRole(.detail)
            if runtime.id == model.registrations.defaultPHPID {
                Label("Default", systemImage: "checkmark.circle.fill")
                    .font(TextRole.detail.font.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("PHP \(runtime.version) is the default")
            }
        }
    }

    @ViewBuilder private func details(_ runtime: DevelopmentRuntime) -> some View {
        ValueRow("CLI", value: runtime.cliPath, isCode: true)
        ValueRow("FPM", value: runtime.fpmPath, isCode: true)
        ValueRow("Architectures", value: runtime.architectures.map(\.rawValue).joined(separator: ", "))
        ActionRow("CLI extensions", detail: runtime.cliExtensions.joined(separator: ", ")) { EmptyView() }
        ActionRow("FPM extensions", detail: runtime.fpmExtensions.joined(separator: ", ")) { EmptyView() }
        ActionRow("Registration", detail: "The runtime files stay on disk.") {
            Button("Remove Registration…", role: .destructive) {
                model.confirmation = .removePHP(runtime)
            }
            .disabled(!model.isIdle)
            .accessibilityLabel("Remove PHP \(runtime.version) registration")
        }
    }
}

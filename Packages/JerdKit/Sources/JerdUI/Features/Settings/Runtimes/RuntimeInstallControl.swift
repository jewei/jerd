import JerdDesign
import JerdRuntimes
import SwiftUI

/// The install control of the selected release: Installed, Install and Use with Install Only
/// for PHP, or one install button.
struct RuntimeInstallControl: View {
    let model: RuntimesModel
    let release: RuntimeRelease

    var body: some View {
        if model.inventory.isInstalled(release) {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(TextRole.detail.font)
                .foregroundStyle(.secondary)
        } else if release.kind == .php {
            HStack(spacing: Spacing.tight) {
                installButton(RuntimeCopy.installTitle(.php, hasInstalledVersion: true), useAsDefault: true)
                Menu {
                    Button("Install Only") { model.install(release, useAsDefault: false) }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(!model.canChangeRuntimes)
                .help("More install options")
                .accessibilityLabel("More install options")
            }
        } else {
            let hasVersion = !model.inventory.installedVersions(release.kind).isEmpty
            installButton(RuntimeCopy.installTitle(release.kind, hasInstalledVersion: hasVersion), useAsDefault: true)
        }
    }

    private func installButton(_ title: String, useAsDefault: Bool) -> some View {
        Button(title) {
            model.install(release, useAsDefault: useAsDefault)
        }
        .disabled(!model.canChangeRuntimes)
        .accessibilityLabel("\(title), \(release.kind.title) \(release.versionLabel)")
        .accessibilityIdentifier(AccessibilityIdentifier.make("runtimes", release.kind.rawValue, "install"))
    }
}

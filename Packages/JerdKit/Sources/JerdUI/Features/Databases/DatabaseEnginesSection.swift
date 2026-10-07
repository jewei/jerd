import JerdDatabases
import JerdDesign
import SwiftUI

/// Which database engines are installed. An engine without a runtime offers its pinned download
/// with the size; a running installation shows its progress and Cancel here.
struct DatabaseEnginesSection: View {
    let model: DatabasesModel
    @Environment(\.isQuitting) private var isQuitting

    /// The widest the list grows, so it reads as one group under the empty state.
    static let maximumWidth: CGFloat = 460

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                ForEach(Array(DatabaseEngine.allCases.enumerated()), id: \.element) { index, engine in
                    if index > 0 { Divider() }
                    row(for: engine)
                }
            }
            .padding(Spacing.small)
        } label: {
            Text("Database Engines")
                .textRole(.rowTitle)
                .accessibilityAddTraits(.isHeader)
        }
        .controlSize(.regular)
        .frame(maxWidth: Self.maximumWidth)
        .accessibilityIdentifier("databases.engines")
    }

    @ViewBuilder private func row(for engine: DatabaseEngine) -> some View {
        if let installation = model.runtimeInstallation, installation.engine == engine {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(engine.title).textRole(.rowTitle)
                DatabaseRuntimeProgressRow(
                    installation: installation, cancel: installation.addsService ? nil : model.cancelRuntimeInstall)
            }
        } else if let offer = model.offer(for: engine) {
            ActionRow(engine.title, detail: DatabaseRuntimeCopy.notInstalledDetail(offer)) {
                Button(DatabaseRuntimeCopy.installTitle(engine)) { model.requestRuntimeInstall(engine) }
                    .disabled(isQuitting || !model.canInstallRuntime)
                    .help(DatabaseRuntimeCopy.confirmationMessage(offer))
                    .accessibilityIdentifier(AccessibilityIdentifier.make("databases", engine.rawValue, "install"))
            }
        } else {
            ActionRow(engine.title, detail: installedDetail(engine)) {
                Image(systemName: isInstalled(engine) ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(isInstalled(engine) ? Color.green : Color.secondary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func isInstalled(_ engine: DatabaseEngine) -> Bool { model.availableEngines.contains(engine) }

    private func installedDetail(_ engine: DatabaseEngine) -> String {
        let versions = model.configuration.runtimes.filter { $0.engine == engine }.map(\.version)
        return versions.isEmpty ? "Not installed." : "Installed: \(versions.joined(separator: ", "))."
    }
}

import JerdDesign
import JerdManifest
import JerdRuntimes
import SwiftUI

/// The rows of a check that found releases: the release picker with its install control, and
/// how the selected release is verified.
struct RuntimeReleaseRows: View {
    let model: RuntimesModel
    let kind: RuntimeKind

    var body: some View {
        if let check = model.checks[kind], let release = model.selectedRelease(kind) {
            ActionRow("Available") {
                Picker("\(kind.title) version", selection: selection) {
                    ForEach(check.releases) { candidate in
                        Text(RuntimeCopy.releaseLabel(candidate, isInstalled: model.inventory.isInstalled(candidate)))
                            .tag(candidate.id)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier(AccessibilityIdentifier.make("runtimes", kind.rawValue, "release"))
                RuntimeInstallControl(model: model, release: release)
            }
            ActionRow("Release", detail: RuntimeCopy.verificationDetail(release)) {
                Link("Release Source", destination: release.releasePage)
                    .accessibilityLabel("\(kind.title) release source")
            }
        }
    }

    private var selection: Binding<String> {
        Binding {
            model.selections[kind] ?? ""
        } set: { id in
            model.selections[kind] = id
        }
    }
}

import JerdDesign
import SwiftUI

/// RustFS while it is not installed: the pinned version with its download size and Install
/// RustFS…, or the running installation with its progress and Cancel. Nothing downloads before the
/// user confirms.
struct StorageRuntimeSection: View {
    let model: StorageModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        Section {
            if let installation = model.runtimeInstallation {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text("RustFS").textRole(.rowTitle)
                    RuntimeInstallProgressRow(installation, cancel: model.cancelRuntimeInstall)
                }
            } else if let offer = model.runtimeOffer {
                ActionRow("RustFS", detail: StorageRuntimeCopy.notInstalledDetail(offer)) {
                    Button(StorageRuntimeCopy.installTitle) { model.requestRuntimeInstall() }
                        .disabled(isQuitting || !model.canInstallRuntime)
                        .help(
                            model.runtimeInstallElsewhere?()
                                ?? StorageRuntimeCopy.confirmationMessage(
                                    StorageRuntimeRequest(offer: offer, startsStorage: false))
                        )
                        .accessibilityIdentifier("storage.install-runtime")
                }
            }
        } header: {
            Text("Runtime")
        } footer: {
            FormFooter(StorageRuntimeCopy.footer(reuses: model.runtimeOffer?.reusesInstalledCopy == true))
        }
    }
}

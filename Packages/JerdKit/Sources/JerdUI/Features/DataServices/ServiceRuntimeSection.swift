import JerdDesign
import SwiftUI

/// The runtime of a service page (RustFS, Mailpit) while it is not installed: the pinned version
/// with its download size and Install…, or the running installation with its progress and Cancel.
/// Nothing downloads before the user confirms. The Storage and Mail pages share it.
struct ServiceRuntimeSection: View {
    let copy: ServiceRuntimeCopy
    let offer: ServiceRuntimeOffer?
    let installation: ServiceRuntimeInstallation?
    let canInstall: Bool
    /// Why Install waits for another page, or nil.
    let elsewhere: String?
    /// The stable name of the page, for example `storage`.
    let identifier: String
    let install: @MainActor () -> Void
    let cancel: @MainActor () -> Void
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        Section {
            if let installation {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(copy.runtime).textRole(.rowTitle)
                    RuntimeInstallProgressRow(installation, identifier: identifier, cancel: cancel)
                }
            } else if let offer {
                ActionRow(copy.runtime, detail: copy.notInstalledDetail(offer)) {
                    Button(copy.installTitle, action: install)
                        .disabled(isQuitting || !canInstall)
                        .help(
                            elsewhere
                                ?? copy.confirmationMessage(ServiceRuntimeRequest(offer: offer, startsService: false))
                        )
                        .accessibilityIdentifier("\(identifier).install-runtime")
                }
            }
        } header: {
            Text("Runtime")
        } footer: {
            FormFooter(copy.footer(reuses: offer?.reusesInstalledCopy == true))
        }
    }
}

extension ServiceRuntimeSection {
    /// The section of the Storage page.
    init(model: StorageModel) {
        self.init(
            copy: .storage, offer: model.runtimeOffer, installation: model.runtimeInstallation,
            canInstall: model.canInstallRuntime, elsewhere: model.runtimeInstallElsewhere?(), identifier: "storage",
            install: { model.requestRuntimeInstall() }, cancel: model.cancelRuntimeInstall)
    }

    /// The section of the Mail page.
    init(model: MailModel) {
        self.init(
            copy: .mail, offer: model.runtimeOffer, installation: model.runtimeInstallation,
            canInstall: model.canInstallRuntime, elsewhere: model.runtimeInstallElsewhere?(), identifier: "mail",
            install: { model.requestRuntimeInstall() }, cancel: model.cancelRuntimeInstall)
    }
}

import JerdDesign
import JerdManifest
import SwiftUI

/// Dashboard › Runtimes: one section per runtime kind, in catalog order.
struct RuntimesPage: View {
    let model: RuntimesModel

    var body: some View {
        FormPage {
            PageHeader(
                "Runtimes", subtitle: "Manage the tools that power your local environment.",
                secondaryActions: [checkAction]
            ) {
                if model.isChecking {
                    BusyIndicator("Checking for runtime updates")
                }
            }
        } messages: {
            if let elsewhere = model.runtimeInstallElsewhere?() {
                InlineMessage(elsewhere, kind: .info, style: .banner, identifier: "runtimes.installing-elsewhere")
            }
            if let installation = model.installation {
                InlineMessage(
                    "Installing \(installation.kind.title). Other runtime changes wait until it finishes.", kind: .info,
                    style: .banner, identifier: "runtimes.installing")
            }
            if model.checks.isEmpty, !model.isChecking {
                InlineMessage(
                    RuntimeCopy.notCheckedMessage, kind: .info, style: .banner, identifier: "runtimes.not-checked")
            }
            OperationFailureBanner(operation: model.operation, identifier: "runtimes.error") {
                model.dismissFailure()
            }
        } content: {
            ForEach(RuntimeKind.allCases) { kind in
                RuntimeSection(model: model, kind: kind)
            }
        }
        // Advanced and the services can change what is installed, so read it each time.
        .task { await model.load() }
        .confirmationDialog(
            model.pendingOnDemandInstall.map { RuntimeInstallCopy.confirmationTitle($0.title) } ?? "",
            isPresented: isConfirmingInstall, titleVisibility: .visible, presenting: model.pendingOnDemandInstall
        ) { _ in
            Button(RuntimeInstallCopy.confirmTitle(reuses: model.reusesInstalledCopy(model.pendingOnDemandInstall))) {
                model.confirmOnDemandInstall()
            }
            Button("Cancel", role: .cancel) { model.pendingOnDemandInstall = nil }
        } message: { release in
            Text(RuntimeInstallCopy.confirmationMessage(release, reuses: model.reusesInstalledCopy(release)))
        }
    }

    private var isConfirmingInstall: Binding<Bool> {
        Binding {
            model.pendingOnDemandInstall != nil
        } set: { isPresented in
            if !isPresented { model.pendingOnDemandInstall = nil }
        }
    }

    private var checkAction: PageAction {
        PageAction(
            RuntimeCopy.checkTitle, systemImage: "arrow.clockwise", isEnabled: model.canCheck,
            identifier: "runtimes.check"
        ) {
            model.check()
        }
    }
}

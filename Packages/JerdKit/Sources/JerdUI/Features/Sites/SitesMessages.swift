import JerdDesign
import SwiftUI

/// The banners of the Sites pages: the failed operation, the environment failure when it
/// says something else, the offer to update a CA that can sign any name, and the system setup
/// state. Each message shows once. A pending
/// recovery has no banner button: the header's primary action opens Advanced. A setup that the
/// helper could not report offers its remedy: Reconnect Helper…, or Open Login Items and Check Again.
struct SitesMessages: View {
    let model: SitesModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        OperationFailureBanner(operation: model.operation, identifier: "sites.error") {
            model.dismissFailure()
        }
        if case .failed(let message) = model.environment.state, message != model.operation.failureMessage {
            InlineMessage(
                message, kind: .error, title: "The sites stopped", style: .banner, identifier: "sites.environment-error"
            )
        }
        if model.needsCAUpdate {
            InlineMessage(
                "The current Jerd CA can sign certificates for any website. Update it to a CA for .test "
                    + "hostnames only. Then a stolen CA key cannot fake other websites.",
                kind: .info, title: "Limit the Jerd CA to .test sites", style: .banner,
                action: PageAction(
                    "Update CA…", isEnabled: model.canChangeSystem && !isQuitting,
                    help: "Trust a new CA for .test hostnames and remove the current CA",
                    identifier: "sites.update-ca"
                ) { model.beginCAUpdate() }, identifier: "sites.ca-update")
        }
        if let setup = model.systemSetupState {
            InlineMessage(
                setup.message, kind: setup.kind, title: setup.title, style: .banner, action: remedyAction(setup),
                secondaryAction: followUpAction(setup), identifier: "sites.system-setup")
        }
    }

    private func remedyAction(_ setup: SystemSetupState) -> PageAction? {
        switch setup.remedy {
        case .reconnectHelper:
            PageAction(
                "Reconnect Helper…", isEnabled: model.canChangeSystem && !isQuitting,
                help: "Register the Jerd helper again. Host entries and certificate settings stay.",
                identifier: "sites.system-setup.reconnect"
            ) { model.confirmation = .reconnectHelper }
        case .openLoginItems:
            PageAction(
                "Open Login Items", help: "Open Login Items & Extensions in System Settings",
                identifier: "sites.system-setup.login-items"
            ) { model.openLoginItems() }
        case nil: nil
        }
    }

    private func followUpAction(_ setup: SystemSetupState) -> PageAction? {
        guard setup.remedy == .openLoginItems else { return nil }
        return PageAction(
            "Check Again", isEnabled: model.canCheckSetupAgain, help: "Read the HTTPS setup again",
            identifier: "sites.system-setup.check-again"
        ) { model.checkSetupAgain() }
    }
}

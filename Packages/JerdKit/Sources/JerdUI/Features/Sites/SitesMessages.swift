import JerdDesign
import SwiftUI

/// The banners of the Sites pages: the failed operation, the environment failure when it
/// says something else, and the system setup state. Each message shows once.
struct SitesMessages: View {
    let state: AppState
    let model: SitesModel

    var body: some View {
        OperationFailureBanner(operation: model.operation, identifier: "sites.error") {
            model.dismissFailure()
        }
        if case .failed(let message) = model.environment.state, message != model.operation.failureMessage {
            InlineMessage(message, kind: .error, title: "The sites stopped", style: .banner, identifier: "sites.environment-error")
        }
        if let setup = model.systemSetupState {
            InlineMessage(
                setup.message, kind: setup.kind, title: setup.title, style: .banner, action: advancedAction(setup),
                identifier: "sites.system-setup")
        }
    }

    private func advancedAction(_ setup: SystemSetupState) -> PageAction? {
        guard setup.opensAdvanced else { return nil }
        return PageAction("Open Advanced", identifier: "sites.open-advanced") {
            state.navigation.show(.dashboard(.advanced))
        }
    }
}

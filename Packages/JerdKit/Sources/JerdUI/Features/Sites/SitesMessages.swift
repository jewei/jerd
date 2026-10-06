import JerdDesign
import SwiftUI

/// The banners of the Sites pages: the failed operation, the environment failure when it
/// says something else, and the system setup state. Each message shows once. A pending
/// recovery has no banner button: the header's primary action opens Advanced.
struct SitesMessages: View {
    let model: SitesModel

    var body: some View {
        OperationFailureBanner(operation: model.operation, identifier: "sites.error") {
            model.dismissFailure()
        }
        if case .failed(let message) = model.environment.state, message != model.operation.failureMessage {
            InlineMessage(
                message, kind: .error, title: "The sites stopped", style: .banner, identifier: "sites.environment-error"
            )
        }
        if let setup = model.systemSetupState {
            InlineMessage(
                setup.message, kind: setup.kind, title: setup.title, style: .banner, identifier: "sites.system-setup")
        }
    }
}

import JerdDesign
import SwiftUI

/// The banners of the Mail page: a failed load, the service state, a missing runtime, and the
/// last failed operation. Each problem shows once.
struct MailPageMessages: View {
    let model: MailModel

    var body: some View {
        if let message = model.loadState.failureMessage {
            InlineMessage(message, kind: .error, style: .banner, identifier: "mail.load-error")
        } else if model.loadState.isLoaded, !model.hasRuntime {
            InlineMessage(
                "Mailpit is not installed. Install it in Runtimes to start the inbox.", kind: .info, style: .banner,
                action: PageAction("View Runtimes", identifier: "mail.view-runtimes") { model.showRuntimes() },
                identifier: "mail.no-runtime")
        }
        ServiceStateBanner(state: model.state, subject: "Mail", stopTitle: "Stop Mail", identifier: "mail")
        OperationFailureBanner(operation: model.operation, identifier: "mail.error") {
            model.dismissFailure()
        }
    }
}

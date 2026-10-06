import JerdDesign
import SwiftUI

/// The banners that both Storage pages share: a failed load, a missing runtime, the service
/// state, a cancelled save that still runs, and the last failed operation.
struct StoragePageMessages: View {
    let model: StorageModel

    var body: some View {
        if let message = model.loadState.failureMessage {
            InlineMessage(message, kind: .error, style: .banner, identifier: "storage.load-error")
        } else if model.loadState.isLoaded, !model.hasRuntime {
            InlineMessage(
                "RustFS is not installed. Install it in Runtimes to start storage.", kind: .info, style: .banner,
                action: PageAction("View Runtimes", identifier: "storage.view-runtimes") { model.showRuntimes() },
                identifier: "storage.no-runtime")
        }
        ServiceStateBanner(state: model.state, subject: "Storage", stopTitle: "Stop Storage", identifier: "storage")
        if let message = model.cancelledSaveMessage {
            InlineMessage(message, kind: .info, style: .banner, identifier: "storage.cancelled-save")
        }
        OperationFailureBanner(operation: model.operation, identifier: "storage.error") {
            model.dismissFailure()
        }
    }
}

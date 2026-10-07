import JerdDesign
import SwiftUI

/// The banners that both Storage pages share: a failed load, a missing runtime that Jerd cannot
/// install itself (with the reason of a failed bundled setup), the result of the last RustFS
/// installation, the service state, a cancelled save that still runs, and the last failed operation.
struct StoragePageMessages: View {
    static let runtimeCopy = MissingRuntimeBanner.Copy(
        runtime: "RustFS", failedTitle: "RustFS setup failed", purpose: "to start storage", identifier: "storage")

    let model: StorageModel

    var body: some View {
        if let message = model.loadState.failureMessage {
            InlineMessage(message, kind: .error, style: .banner, identifier: "storage.load-error")
        } else if model.loadState.isLoaded, !model.hasRuntime,
            model.runtimeOffer == nil || model.runtimeSetupFailure != nil
        {
            MissingRuntimeBanner(
                copy: Self.runtimeCopy, setupFailure: model.runtimeSetupFailure, showRuntimes: model.showRuntimes)
        }
        if let notice = model.runtimeNotice {
            InlineMessage(
                notice.message, kind: notice.isFailure ? .error : .info,
                title: notice.isFailure ? StorageRuntimeCopy.failedTitle : nil, style: .banner,
                identifier: "storage.install-notice", dismiss: model.dismissRuntimeNotice)
        }
        ServiceStateBanner(
            state: model.state, subject: "Storage", stopTitle: "Stop Storage", identifier: "storage",
            files: model.files, openLog: model.openLog)
        if let message = model.cancelledSaveMessage {
            InlineMessage(message, kind: .info, style: .banner, identifier: "storage.cancelled-save")
        }
        OperationFailureBanner(operation: model.operation, identifier: "storage.error") {
            model.dismissFailure()
        }
    }
}

import JerdDesign
import SwiftUI

/// The banners of the Mail page: a failed load, a missing runtime that Jerd cannot install itself
/// (with the reason of a failed bundled setup), the result of the last Mailpit installation, the
/// service state, a cancelled save that still runs, and the last failed operation. Each problem
/// shows once.
struct MailPageMessages: View {
    static let runtimeCopy = MissingRuntimeBanner.Copy(
        runtime: "Mailpit", failedTitle: "Mailpit setup failed", purpose: "to start the inbox", identifier: "mail")

    let model: MailModel

    var body: some View {
        if let message = model.loadState.failureMessage {
            InlineMessage(message, kind: .error, style: .banner, identifier: "mail.load-error")
        } else if model.loadState.isLoaded, !model.hasRuntime,
            model.runtimeOffer == nil || model.runtimeSetupFailure != nil
        {
            MissingRuntimeBanner(
                copy: Self.runtimeCopy, setupFailure: model.runtimeSetupFailure, showRuntimes: model.showRuntimes)
        }
        if let notice = model.runtimeNotice {
            InlineMessage(
                notice.message, kind: notice.isFailure ? .error : .info,
                title: notice.isFailure ? ServiceRuntimeCopy.mail.failedTitle : nil, style: .banner,
                identifier: "mail.install-notice", dismiss: model.dismissRuntimeNotice)
        }
        ServiceStateBanner(
            state: model.state, subject: "Mail", stopTitle: "Stop Mail", identifier: "mail", files: model.files,
            openLog: model.openLog)
        if let message = model.cancelledSaveMessage {
            InlineMessage(message, kind: .info, style: .banner, identifier: "mail.cancelled-save")
        }
        OperationFailureBanner(operation: model.operation, identifier: "mail.error") {
            model.dismissFailure()
        }
    }
}

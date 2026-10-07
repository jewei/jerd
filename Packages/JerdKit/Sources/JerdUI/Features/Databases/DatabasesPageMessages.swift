import JerdDatabases
import JerdDesign
import SwiftUI

/// The banners that every Databases page shares: a failed bundled runtime setup while an engine
/// still has no runtime, the state of the shown service, the registry change in progress, a
/// cancelled save that still runs, and the last failed operation.
struct DatabasesPageMessages: View {
    static let runtimeCopy = MissingRuntimeBanner.Copy(
        runtime: "the missing engines", failedTitle: "Database runtime setup failed",
        purpose: "to add their services", identifier: "databases")

    let model: DatabasesModel
    /// The service of the page, or nil on the empty page.
    let service: DatabaseService?

    var body: some View {
        if let failure = model.visibleRuntimeSetupFailure {
            MissingRuntimeBanner(copy: Self.runtimeCopy, setupFailure: failure, showRuntimes: model.showRuntimes)
        }
        // The engine list of the empty page shows the progress itself; a service page needs a banner.
        if service != nil, let installation = model.runtimeInstallation, !installation.addsService {
            InlineMessage(
                installation.message, kind: .info, style: .banner,
                action: PageAction(
                    "Cancel", accessibilityLabel: "Cancel \(installation.engine.title) installation",
                    identifier: "databases.cancel-install", perform: model.cancelRuntimeInstall),
                identifier: "databases.installing")
        }
        if let notice = model.runtimeNotice {
            InlineMessage(
                notice.message, kind: notice.isFailure ? .error : .info,
                title: notice.isFailure ? "\(notice.engine.title) was not installed" : nil, style: .banner,
                identifier: "databases.install-notice", dismiss: model.dismissRuntimeNotice)
        }
        if let service {
            ServiceStateBanner(
                state: model.state(of: service.id), subject: service.name, stopTitle: "Stop Service",
                identifier: "database", files: model.files[service.id], openLog: { model.openLog(service.id) })
        }
        if let message = model.operation.workingMessage {
            InlineMessage(message, kind: .info, style: .banner, identifier: "databases.working")
        }
        if let message = model.cancelledSaveMessage {
            InlineMessage(message, kind: .info, style: .banner, identifier: "databases.cancelled-save")
        }
        OperationFailureBanner(operation: model.operation, identifier: "databases.error") {
            model.dismissFailure()
        }
    }
}

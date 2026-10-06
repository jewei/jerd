import JerdDatabases
import JerdDesign
import SwiftUI

/// The banners that every Databases page shares: the state of the shown service, the registry
/// change in progress, a cancelled save that still runs, and the last failed operation.
struct DatabasesPageMessages: View {
    let model: DatabasesModel
    /// The service of the page, or nil on the empty page.
    let service: DatabaseService?

    var body: some View {
        if let service {
            ServiceStateBanner(
                state: model.state(of: service.id), subject: service.name, stopTitle: "Stop Service",
                identifier: "database")
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

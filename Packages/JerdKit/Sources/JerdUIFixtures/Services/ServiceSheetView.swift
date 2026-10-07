import JerdUI
import SwiftUI

/// One service sheet alone, for its snapshot.
struct ServiceSheetView: View {
    let scenario: ServiceScenario
    let state: AppState

    var body: some View {
        switch scenario {
        case .databaseEditor, .databaseEditorInvalid, .databaseEditorInstall, .databaseEditorInstalling,
            .databaseEditorInstallFailed:
            DatabaseEditorSheet(model: state.databases)
        case .retainedDatabases: RetainedDatabasesSheet(model: state.databases)
        case .restoreDatabase: RestoreDatabaseSheet(model: state.databases)
        case .addBucket, .addBucketInvalid: AddBucketSheet(model: state.storage)
        case .storagePorts: StoragePortsSheet(model: state.storage)
        case .mailPorts: MailPortsSheet(model: state.mail)
        default: EmptyView()
        }
    }
}

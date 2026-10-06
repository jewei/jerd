import Foundation
import JerdDatabases
import JerdServiceKit
import JerdUI

/// The window and sheet states of the Databases, Storage, and Mail sections, for snapshots.
public enum ServiceScenario: String, CaseIterable, Sendable {
    case databasesEmpty = "databases-empty"
    case databasesNoRuntimes = "databases-no-runtimes"
    case databases
    case databaseStopped = "database-stopped"
    case databaseFailed = "database-failed"
    case databaseStuck = "database-stuck"
    case databaseStarting = "database-starting"
    case databaseRuntimeMissing = "database-runtime-missing"
    case databasesLoadFailed = "databases-load-failed"
    case databasesLong = "databases-long"
    case databaseEditor = "database-editor"
    case databaseEditorInvalid = "database-editor-invalid"
    case retainedDatabases = "retained-databases"
    case restoreDatabase = "restore-database"
    case storage
    case storageEmpty = "storage-empty"
    case storageNoRuntime = "storage-no-runtime"
    case storageStuck = "storage-stuck"
    case storageFailed = "storage-failed"
    case bucket
    case bucketIncomplete = "bucket-incomplete"
    case addBucket = "add-bucket"
    case addBucketInvalid = "add-bucket-invalid"
    case storagePorts = "storage-ports"
    case mail
    case mailStopped = "mail-stopped"
    case mailStuck = "mail-stuck"
    case mailNoRuntime = "mail-no-runtime"
    case mailPorts = "mail-ports"
    case advancedCommandLineTools = "advanced-command-line-tools"

    /// The kind of snapshot: a full window or one sheet alone.
    public enum Kind: Sendable {
        case window
        case sheet
    }

    public var kind: Kind {
        switch self {
        case .databaseEditor, .databaseEditorInvalid, .retainedDatabases, .restoreDatabase, .addBucket,
            .addBucketInvalid, .storagePorts, .mailPorts:
            .sheet
        default: .window
        }
    }

    /// The fixture with the scenario's service data and navigation. Run `prepare` before rendering.
    @MainActor
    public func makeFixture() -> AppFixture {
        let fixture = AppFixture(
            suiteName: "dev.jerd.fixtures.services", features: SampleFeatures.all(.populated), services: ports())
        fixture.state.navigation.show(destination)
        return fixture
    }

    private var destination: Destination {
        switch self {
        case .databases, .databasesLong, .databaseEditor, .databaseEditorInvalid, .retainedDatabases,
            .restoreDatabase:
            .item(.database(SampleServices.studioID))
        case .databaseStopped, .databaseFailed, .databaseStarting, .databaseRuntimeMissing:
            .item(.database(SampleServices.reportingID))
        case .databaseStuck: .item(.database(SampleServices.cacheID))
        case .databasesEmpty, .databasesNoRuntimes, .databasesLoadFailed: .section(.databases)
        case .storage, .storageEmpty, .storageNoRuntime, .storageStuck, .storageFailed, .addBucket,
            .addBucketInvalid, .storagePorts:
            .section(.storage)
        case .bucket: .item(.bucket("studio-public-assets"))
        case .bucketIncomplete: .item(.bucket("reports-archive"))
        case .mail, .mailStopped, .mailStuck, .mailNoRuntime, .mailPorts: .section(.mail)
        case .advancedCommandLineTools: .dashboard(.advanced)
        }
    }
}

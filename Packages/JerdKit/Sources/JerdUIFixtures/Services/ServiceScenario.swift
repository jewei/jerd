import Foundation
import JerdDatabases
import JerdServiceKit
import JerdSnapshotSupport
import JerdUI

/// The window and sheet states of the Databases, Storage, and Mail sections, for snapshots.
public enum ServiceScenario: String, CaseIterable, Sendable {
    case databasesEmpty = "databases-empty"
    case databasesNoRuntimes = "databases-no-runtimes"
    /// The bundled setup failed at launch: only MySQL has a runtime.
    case databasesSetupFailed = "databases-setup-failed"
    case databases
    case databaseStopped = "database-stopped"
    case databaseFailed = "database-failed"
    case databaseStuck = "database-stuck"
    case databaseStarting = "database-starting"
    case databaseRuntimeMissing = "database-runtime-missing"
    case databasesLoadFailed = "databases-load-failed"
    case databasesLong = "databases-long"
    /// The user cancelled Edit while its save still runs: the page says why Edit is off.
    case databaseCancelledSave = "database-cancelled-save"
    /// A quit waits for storage: the Databases controls are off before their own stage.
    case databaseQuitting = "database-quitting"
    case databaseEditor = "database-editor"
    case databaseEditorInvalid = "database-editor-invalid"
    case retainedDatabases = "retained-databases"
    case restoreDatabase = "restore-database"
    case storage
    case storageEmpty = "storage-empty"
    case storageNoRuntime = "storage-no-runtime"
    case storageSetupFailed = "storage-setup-failed"
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
    case mailSetupFailed = "mail-setup-failed"
    case mailPorts = "mail-ports"
    /// A quit waits for storage: the Mail controls are off before their own stage.
    case mailQuitting = "mail-quitting"
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

    /// Long pages also render scrolled to their end at both window sizes.
    public var showsEnd: Bool {
        switch self {
        case .databases, .bucket, .storage, .mail, .advancedCommandLineTools: true
        default: false
        }
    }

    /// Every sheet, and at least one scenario of each page, also renders with Increase Contrast.
    package var snapshotAppearances: [SnapshotAppearance] {
        switch self {
        case .databases, .databasesEmpty, .databasesSetupFailed, .databaseRuntimeMissing, .databaseStuck, .storage,
            .bucket, .storageStuck, .mail, .mailSetupFailed:
            SnapshotAppearance.allCases
        default: kind == .sheet ? SnapshotAppearance.allCases : SnapshotAppearance.standard
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

    package var destination: Destination {
        switch self {
        case .databases, .databasesLong, .databaseEditor, .databaseEditorInvalid, .retainedDatabases,
            .restoreDatabase:
            .item(.database(SampleServices.studioID))
        case .databaseStopped, .databaseFailed, .databaseStarting, .databaseRuntimeMissing,
            .databaseCancelledSave, .databaseQuitting:
            .item(.database(SampleServices.reportingID))
        case .databaseStuck: .item(.database(SampleServices.cacheID))
        case .databasesEmpty, .databasesNoRuntimes, .databasesSetupFailed, .databasesLoadFailed: .section(.databases)
        case .storage, .storageEmpty, .storageNoRuntime, .storageSetupFailed, .storageStuck, .storageFailed,
            .addBucket, .addBucketInvalid, .storagePorts:
            .section(.storage)
        case .bucket: .item(.bucket("studio-public-assets"))
        case .bucketIncomplete: .item(.bucket("reports-archive"))
        case .mail, .mailStopped, .mailStuck, .mailNoRuntime, .mailSetupFailed, .mailPorts, .mailQuitting:
            .section(.mail)
        case .advancedCommandLineTools: .dashboard(.advanced)
        }
    }
}

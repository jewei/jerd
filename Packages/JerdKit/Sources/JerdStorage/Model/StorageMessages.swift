import JerdFoundation
import JerdServiceKit

/// Every user message of the storage area, in one place.
public enum StorageMessages {
    // MARK: Settings

    static let bucketNameInvalid = JerdError.invalid(
        "Use 3–63 lowercase letters, numbers, dots, or hyphens. Start and end with a letter or number. "
            + "Do not use an IP address, adjacent dots, or a reserved S3 name.")
    static let settingsInvalid = JerdError.invalid(
        "Storage settings need unique buckets, two different ports from 1024 to 65535, and a supported format.")
    static let runtimeRecordInvalid = JerdError.invalid("The RustFS runtime record is invalid.")
    static let runtimeNotReplaceable = JerdError.invalid(
        "The saved RustFS runtime cannot be replaced. Stored objects were preserved.")
    static let runtimeChanged = JerdError.invalid("The RustFS runtime changed. Stored objects were preserved.")
    static let recoveryWithoutRuntime = JerdError.corrupt(
        "Storage settings have no RustFS runtime, but a runtime update needs recovery. The files were preserved.")

    // MARK: Credentials

    static let credentialsUnavailable = JerdError.unavailable("Cannot generate storage credentials.")
    static let credentialsInvalid = JerdError.corrupt("The storage credentials are invalid. The file was preserved.")
    static let credentialsMissing = JerdError.corrupt("Storage credentials are missing. Existing data was preserved.")
    static let startOnce = JerdError.unavailable("Start storage once to create its data folder.")

    // MARK: Manager

    static let busy = "Wait for the current storage operation to finish."
    static let notLoaded = JerdError.unavailable("Load storage settings before changing the service.")
    static let updatePending = JerdError.unavailable(
        "Stop and start storage to recover its unfinished runtime update.")
    static let runtimeMissing = JerdError.unavailable("The RustFS runtime is not installed.")
    static let stopBeforeEditing = JerdError.unavailable("Stop storage before changing its ports.")
    static let startBeforeBuckets = JerdError.unavailable("Start storage before using its buckets.")
    static let onlyUnfinishedRetry = JerdError.invalid("Only an unfinished bucket setup can be retried.")
    static let bucketsMissingAfterUpdate = JerdError.processFailed(
        "The updated storage service did not return all registered buckets.")

    static func alreadyRegistered(_ name: String) -> JerdError {
        .invalid("A bucket named \(name) is already registered. Select it in Storage.")
    }

    static func alreadyInRustFS(_ name: String) -> JerdError {
        .invalid("A bucket named \(name) already exists in RustFS. No settings were changed.")
    }

    // MARK: Start

    static let versionMismatch = "The RustFS executable does not match the saved version."
    static let dataChanged = JerdError.corrupt(
        "Storage data or credentials changed, or belong to a different RustFS version. "
            + "Existing files were preserved.")
    static let requiredFileInvalid = JerdError.corrupt(
        "A required storage file is invalid. Existing files were preserved.")
    static let identityMismatch = JerdError.invalid(
        "The data folder belongs to a different RustFS version. It was preserved.")
    static let untracked = JerdError.invalid("An untracked storage data folder already exists. It was preserved.")
    static let readinessTimedOut = "RustFS did not become ready within 45 seconds."
    static let noResponse = "RustFS did not answer yet."

    // MARK: S3

    static let invalidPath = JerdError.invalid("Invalid local S3 path.")
    static let sessionEnded = JerdError.unavailable("Storage stopped during the request. Start storage and retry.")
    static let invalidResponse = JerdError.processFailed("RustFS returned an invalid response.")
    static let responseTooLarge = JerdError.processFailed("The RustFS response exceeds the size limit.")
    static let invalidBucketList = JerdError.processFailed("RustFS returned an invalid bucket list.")
    static let accessUnverified = JerdError.processFailed(
        "The bucket access settings could not be verified. Retry setup.")
    static let bucketUnconfirmed = JerdError.processFailed("RustFS did not confirm the new bucket. Retry setup.")

    static func httpStatus(_ status: Int) -> JerdError {
        .processFailed("RustFS returned HTTP \(status). Check the storage log and retry.")
    }

    static func customPolicy(_ name: String) -> JerdError {
        .invalid("Bucket \(name) has a custom access policy. Use the RustFS console to inspect it.")
    }

    /// The messages of the shared manager core.
    static let manager = SingleServiceMessages(
        busy: busy, notLoaded: notLoaded, updatePending: updatePending, runtimeMissing: runtimeMissing,
        runtimeChanged: runtimeChanged, runtimeRecordInvalid: runtimeRecordInvalid,
        recoveryWithoutRuntime: recoveryWithoutRuntime, stopBeforeEditing: stopBeforeEditing)

    // MARK: Runtime update

    /// The words of the shared runtime update messages.
    static let update = RuntimeUpdateTransaction.Messages(
        service: "Storage", restored: "The previous runtime and data were restored.",
        stopBeforeRecovery: "Stop storage before recovering its runtime update.")

    /// The instance messages of the shared lifecycle. Failures add the end of the server log.
    static let instance = ServiceMessages(
        busy: busy, alreadyHasProcess: "Storage already has a process. Stop it before retrying.",
        lockUnavailable: "Cannot lock the storage data folder.",
        lockBusy: "Another Jerd process is using this storage data folder.",
        couldNotStart: "RustFS could not start.", exitedBeforeReady: "RustFS exited before it was ready.",
        exitedDuringCheck: "RustFS exited during its readiness check.", exited: "The RustFS process exited.",
        logUnavailable: "Open the storage log for details.")
}

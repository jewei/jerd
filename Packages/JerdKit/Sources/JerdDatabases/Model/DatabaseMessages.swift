import Foundation
import JerdFoundation
import JerdServiceKit

/// Every user message of the database area, in one place.
public enum DatabaseMessages {
    // MARK: Settings

    static let unsupportedSettings = JerdError.corrupt(
        "Database settings contain an unsupported version or duplicate records or ports.")
    static let runtimeRecordInvalid = JerdError.invalid("The database runtime record is invalid.")
    static let serviceInvalid = JerdError.invalid(
        "Use a service name of 1 to 80 characters and a port from 1024 to 65535.")
    static let runtimeUnavailable = JerdError.unavailable("The selected database runtime is unavailable.")
    static let duplicateName = JerdError.invalid("Each database service needs a unique name.")
    static let reassignedRuntime = JerdError.invalid(
        "Create a separate service to use a different database version. Existing data cannot be reassigned.")
    static let replacedRuntime = JerdError.invalid(
        "An installed database runtime cannot be replaced under the same ID.")
    static let runtimeChanged = JerdError.invalid("The installed database runtime changed under the same ID.")

    /// A port that another registered service uses. This is a user input problem, not corruption.
    static func portConflict(_ port: UInt16, with name: String) -> JerdError {
        .invalid("Port \(port) is already used by \(name). Choose a different port.")
    }

    // MARK: Credentials

    static let credentialsUnavailable = JerdError.unavailable("Cannot create database credentials.")
    static let credentialsInvalid = JerdError.corrupt("The database credential file is invalid. It was preserved.")
    static let credentialsMissing = JerdError.corrupt(
        "The database credentials are missing. Existing data was preserved.")
    static let startOnce = JerdError.unavailable("Start the service once to create its credentials.")

    // MARK: Manager

    static let notLoaded = JerdError.unavailable("Load database settings before changing services.")
    static let notRegistered = JerdError.invalid("The database service is not registered.")
    static let busy = "This database service is busy."
    static let stopBeforeEditing = JerdError.unavailable(
        "Stop the service before editing it. Its database version cannot be changed.")
    static let quitBusy = JerdError.unavailable("Wait for the current database operation to finish before quitting.")

    // MARK: Retained data

    static let alreadyRegisteredOrBusy = JerdError.unavailable("This database is already registered or busy.")
    static let retainedFolderInvalid = JerdError.invalid("The retained database folder is invalid.")
    static let removedRegistrationInvalid = JerdError.corrupt("The removed registration is invalid. It was preserved.")
    static let exactRuntimeUnavailable = JerdError.unavailable(
        "The exact runtime for this retained database is unavailable.")
    static let restoreExactRuntime = JerdError.unavailable(
        "Restore the exact original runtime registration before using this data.")
    static let retainedIncomplete = JerdError.corrupt(
        "The retained database is incomplete or belongs to another runtime. Its files were preserved.")
    static let dataDirectoryInvalid = JerdError.corrupt("The database data directory is missing or invalid.")

    static func retainedName(_ id: UUID) -> String { "Retained database \(id.uuidString.prefix(8))" }

    static func recoveredName(_ engine: DatabaseEngine, _ id: UUID) -> String {
        "Recovered \(engine.title) \(id.uuidString.prefix(6))"
    }

    // MARK: Start

    static let versionMismatch = "The database executable does not match the registered version."
    static let identityMismatch = JerdError.invalid(
        "This data directory belongs to a different database version. It was preserved.")
    static let untracked = JerdError.invalid("An untracked database directory already exists. It was preserved.")
    static let initializedMismatch = JerdError.corrupt(
        "The initialized database directory is missing or does not match this service.")
    static let interrupted = JerdError.corrupt(
        "Database initialization was interrupted. The partial data was preserved. "
            + "Inspect the data folder before creating a new service.")
    static let initializationFailed = "Database initialization failed:"
    static let socketFolder = JerdError.invalid("Cannot create a private database socket directory.")
    static let readinessTimedOut = "Database readiness timed out."
    static let noResponse = "No response from the database."

    /// The instance messages of the shared lifecycle.
    static let instance = ServiceMessages(
        busy: busy, alreadyHasProcess: "This database service already has a process. Stop it before retrying.",
        lockUnavailable: "Cannot lock the database instance.",
        lockBusy: "Another Jerd process is using this database instance.",
        couldNotStart: "The database process could not start.",
        exitedBeforeReady: "The database exited before it was ready.",
        exitedDuringCheck: "The database exited during its readiness check.", exited: "The database process exited.",
        logUnavailable: "Open the service log for details.")
}

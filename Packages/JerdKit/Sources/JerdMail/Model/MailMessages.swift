import JerdFoundation
import JerdServiceKit

/// Every user message of the mail area, in one place.
public enum MailMessages {
    // MARK: Settings

    static let settingsInvalid = JerdError.invalid(
        "Mail settings need two different ports from 1024 to 65535 and a supported format.")
    static let runtimeRecordInvalid = JerdError.invalid("The Mailpit runtime record is invalid.")
    static let runtimeNotReplaceable = JerdError.invalid(
        "The saved Mailpit runtime cannot be replaced. The inbox was preserved.")
    static let runtimeChanged = JerdError.invalid("The Mailpit runtime changed. The existing inbox was preserved.")
    static let recoveryWithoutRuntime = JerdError.corrupt(
        "Mail settings have no Mailpit runtime, but a runtime update needs recovery. The files were preserved.")

    // MARK: Manager

    static let busy = "Wait for the current mail operation to finish."
    static let notLoaded = JerdError.unavailable("Load mail settings before changing the service.")
    static let updatePending = JerdError.unavailable("Stop and start mail to recover its unfinished runtime update.")
    static let runtimeMissing = JerdError.unavailable("The Mailpit runtime is not installed.")
    static let stopBeforeEditing = JerdError.unavailable("Stop the mail service before changing its ports.")
    static let startBeforeTest = JerdError.unavailable("Start the mail service before sending a test email.")
    static let testFailed = "The test email could not be sent:"

    // MARK: Start

    static let versionMismatch = "The Mailpit executable does not match the saved version."
    static let initializedMismatch = JerdError.corrupt(
        "The initialized inbox is missing or belongs to a different Mailpit version. Existing files were preserved.")
    static let identityMismatch = JerdError.invalid(
        "The inbox belongs to a different Mailpit version. It was preserved.")
    static let untracked = JerdError.invalid("An untracked mail inbox already exists. It was preserved.")
    static let databaseNotRegular = JerdError.invalid("The mail database must be a regular file.")
    static let readinessTimedOut = "Mailpit did not pass its SMTP and web checks."
    static let noResponse = "Mailpit did not answer yet."

    // MARK: Runtime update

    /// The words of the shared runtime update messages.
    static let update = RuntimeUpdateTransaction.Messages(
        service: "Mail", restored: "The previous runtime and inbox were restored.",
        stopBeforeRecovery: "Stop mail before recovering its runtime update.")

    /// The instance messages of the shared lifecycle.
    static let instance = ServiceMessages(
        busy: busy, alreadyHasProcess: "The mail service already has a process. Stop it before retrying.",
        lockUnavailable: "Cannot lock the mail inbox.", lockBusy: "Another Jerd process is using this mail inbox.",
        couldNotStart: "The mail process could not start.", exitedBeforeReady: "Mailpit exited before it was ready.",
        exitedDuringCheck: "Mailpit exited during its readiness check.", exited: "The mail process exited.",
        logUnavailable: "Open the mail log for details.")
}

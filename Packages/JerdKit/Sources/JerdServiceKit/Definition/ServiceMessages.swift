import JerdFoundation

/// The user messages that differ between services. Shared messages are static members.
public struct ServiceMessages: Sendable, Equatable {
    /// Another operation of this instance is in progress.
    public var busy: String
    /// A start was requested while a process is owned.
    public var alreadyHasProcess: String
    /// The lock file cannot be opened.
    public var lockUnavailable: String
    /// Another owner holds the lock.
    public var lockBusy: String
    /// The spawn produced no owned process. The log tail follows.
    public var couldNotStart: String
    /// The process exited before the readiness check passed. The log tail follows.
    public var exitedBeforeReady: String
    /// The process exited between readiness and the final check.
    public var exitedDuringCheck: String
    /// Exit detection found that the process exited by itself. The log tail follows.
    public var exited: String
    /// Replaces the log tail when the log cannot be read.
    public var logUnavailable: String

    public init(
        busy: String, alreadyHasProcess: String, lockUnavailable: String, lockBusy: String, couldNotStart: String,
        exitedBeforeReady: String, exitedDuringCheck: String, exited: String, logUnavailable: String
    ) {
        self.busy = busy
        self.alreadyHasProcess = alreadyHasProcess
        self.lockUnavailable = lockUnavailable
        self.lockBusy = lockBusy
        self.couldNotStart = couldNotStart
        self.exitedBeforeReady = exitedBeforeReady
        self.exitedDuringCheck = exitedDuringCheck
        self.exited = exited
        self.logUnavailable = logUnavailable
    }

    /// The lock messages in the form that `InstanceLock` takes.
    public var lock: InstanceLock.Messages {
        InstanceLock.Messages(unavailable: lockUnavailable, busy: lockBusy)
    }

    /// A graceful stop timed out. Jerd never forces a data service to exit.
    public static func stopTimedOut(name: String, timeout: Duration) -> String {
        "\(name) did not stop within \(timeout.components.seconds) seconds. Its process is still tracked. "
            + "Retry Stop; Jerd did not force it to exit."
    }

    /// Appended to the exit reason when the exited leader left a group member that did not stop.
    public static let childStillRunning = "A service child has not stopped. Its data lock was kept. Retry Stop."

    /// The owned child was reaped outside Jerd, so Jerd cannot prove that its group stopped.
    public static let reapedOutside =
        "The service process ended outside Jerd's control. Jerd released the data lock so that "
        + "Advanced → Process recovery can inspect the saved process."

    /// `StartTools` has no initializer runner, so an initializer cannot run as an owned process.
    public static let initializerUnavailable = "This start cannot run an initializer. No process was started."

    /// The initializer was reaped outside Jerd, so its exit status is unknown.
    public static let initializerResultUnknown =
        "The initializer ended outside Jerd's control. Its result is unknown, so its data was not used."

    /// A private file with a secret is still on disk after its step. `details` names each file.
    public static func secretFilesKept(_ details: [String]) -> String {
        "\(details.joined(separator: " ")) It holds a secret. Remove it by hand."
    }

    /// A maintenance lease or a stop request names an operation that is not current.
    public static let staleLease = "The service operation is no longer current. Retry the operation."
}

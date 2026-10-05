/// The kernel-backed identity of one process, saved in active-run records.
///
/// A saved PID alone is never trusted. The start time and user prove that a PID still names the
/// same process; the boot session proves that the system did not restart; the audit token
/// (which contains the PID version) is the only handle used to send a signal.
public struct ProcessIdentity: Codable, Equatable, Hashable, Sendable {
    /// The result of comparing a saved identity with the live system.
    public enum Match: Equatable, Sendable {
        /// The same process still runs.
        case running
        /// The process exited (or is a zombie).
        case exited
        /// The PID now belongs to another process, or the system restarted.
        case replaced
        /// The process cannot be verified, for example after an exec or a failed inspection.
        case unknown
    }

    public let processID: Int32
    public let userID: UInt32
    /// `pbi_start_tvsec`: fixed for the life of the process.
    public let startedSeconds: UInt64
    /// `pbi_start_tvusec`.
    public let startedMicroseconds: UInt64
    /// `kern.boottime` seconds. Written for older Jerd builds, never compared: a clock change moves it.
    public let bootSeconds: Int64
    /// The executable path from `proc_pidpath`.
    public let executable: String
    /// The 8 words of the audit token, or nil when it could not be read.
    public let auditWords: [UInt32]?
    /// `kern.bootsessionuuid`, unique for each system start. Nil in records of older builds.
    public let bootSessionID: String?

    public init(
        processID: Int32, userID: UInt32, startedSeconds: UInt64, startedMicroseconds: UInt64, bootSeconds: Int64,
        executable: String, auditWords: [UInt32]?, bootSessionID: String?
    ) {
        self.processID = processID
        self.userID = userID
        self.startedSeconds = startedSeconds
        self.startedMicroseconds = startedMicroseconds
        self.bootSeconds = bootSeconds
        self.executable = executable
        self.auditWords = auditWords
        self.bootSessionID = bootSessionID
    }

    /// Compares this saved identity with a fresh capture of the same PID.
    ///
    /// A different boot session, user, or start time is `.replaced`. A different executable or
    /// audit token (an exec in place, or lost permission) is `.unknown`, never stale.
    public func compare(with current: ProcessIdentity) -> Match {
        if let saved = bootSessionID, let live = current.bootSessionID, saved != live { return .replaced }
        guard current.userID == userID, current.startedSeconds == startedSeconds,
            current.startedMicroseconds == startedMicroseconds
        else { return .replaced }
        guard current.executable == executable, current.auditWords == auditWords else { return .unknown }
        return .running
    }
}

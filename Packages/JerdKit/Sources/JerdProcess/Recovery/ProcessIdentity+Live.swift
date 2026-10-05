import Darwin
import JerdFoundation

extension ProcessIdentity {
    /// Captures the identity of a live process.
    /// - Throws: `.unavailable` when the process is gone, a zombie, or changed during the capture.
    public static func capture(_ pid: pid_t) throws -> ProcessIdentity {
        guard pid > 1, let before = KernelProcessInfo.bsdInfo(pid).info, before.pbi_status != SZOMB else {
            throw JerdError.unavailable("The process is no longer available for inspection.")
        }
        guard let executable = KernelProcessInfo.executablePath(pid) else {
            throw JerdError.unavailable("Cannot inspect the process executable. No process was signalled.")
        }
        guard let bootSeconds = KernelProcessInfo.bootSeconds() else {
            throw JerdError.unavailable("Cannot inspect the system start time.")
        }
        let auditWords = KernelProcessInfo.auditWords(pid)
        // The process can exit or exec while its path and token are read.
        guard let after = KernelProcessInfo.bsdInfo(pid).info, after.pbi_start_tvsec == before.pbi_start_tvsec,
            after.pbi_start_tvusec == before.pbi_start_tvusec, after.pbi_uid == before.pbi_uid
        else { throw JerdError.unavailable("The process changed during inspection.") }
        return ProcessIdentity(
            processID: pid, userID: before.pbi_uid, startedSeconds: before.pbi_start_tvsec,
            startedMicroseconds: before.pbi_start_tvusec, bootSeconds: bootSeconds, executable: executable,
            auditWords: auditWords, bootSessionID: KernelProcessInfo.bootSessionID())
    }

    /// Compares this saved identity with the process that now has its PID.
    public func liveMatch() -> Match {
        let (info, error) = KernelProcessInfo.bsdInfo(processID)
        if info == nil, error == ESRCH { return .exited }
        if let info, info.pbi_status == SZOMB { return .exited }
        do {
            return compare(with: try Self.capture(processID))
        } catch {
            // A failed capture cannot prove an exit or a replacement.
            return .unknown
        }
    }
}

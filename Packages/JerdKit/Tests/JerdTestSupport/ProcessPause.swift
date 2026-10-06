import Darwin

/// Pauses and inspects test processes, as `kill -STOP` or a job-control stop (`SIGTSTP`) does.
package enum ProcessPause {
    /// True while the kernel reports `pid` as stopped (`SSTOP`).
    package static func isPaused(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.pbi_status == SSTOP
    }

    /// Sends `signal` (`SIGSTOP`, or `SIGTSTP` for a process that keeps its default action) to
    /// `pid` and waits up to `timeout` until the kernel reports it stopped.
    /// - Returns: false when the process did not stop in time.
    package static func pause(_ pid: pid_t, signal: Int32 = SIGSTOP, timeout: Duration = .seconds(5)) async -> Bool {
        guard kill(pid, signal) == 0 else { return false }
        let deadline = ContinuousClock.now + timeout
        while !isPaused(pid) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}

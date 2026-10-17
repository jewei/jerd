import Darwin

/// Inspects whether a test process has ended, so that a test waits for an exit instead of sleeping.
package enum ProcessExit {
    /// True when `pid` is a zombie (`SZOMB`) or no longer exists.
    ///
    /// A zombie still answers `kill(pid, 0)`, so this reads the kernel state. The kernel gives no
    /// BSD info for some zombies; for a test's own process, a failed read also means it has ended.
    package static func hasExited(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return true }
        return info.pbi_status == SZOMB
    }
}

import Darwin

/// The one place that asks the kernel about an own child: `waitid` without reaping, and the final reap.
enum ChildStatus {
    /// Reads the state of child `pid` with `waitid(WEXITED | WNOHANG | WNOWAIT)`. It never reaps.
    ///
    /// A failed call (for example `ECHILD` after an outside reap) is `.notOwned`, never an exit status.
    static func peek(_ pid: pid_t) -> ProcessState {
        var info = siginfo_t()
        var result: Int32
        repeat {
            result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
        } while result < 0 && errno == EINTR
        guard result == 0 else { return .notOwned }
        guard info.si_pid != 0 else { return .running }
        return info.si_code == CLD_EXITED ? .exited(status: info.si_status) : .signalled(signal: info.si_status)
    }

    /// Reaps an exited child. Call only after `peek` reported an exit, so it never blocks.
    static func reap(_ pid: pid_t) {
        var status: Int32 = 0
        while waitpid(pid, &status, WNOHANG) < 0, errno == EINTR {}
    }
}

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
        return state(code: info.si_code, status: info.si_status)
    }

    /// Maps a `waitid` report to a state.
    ///
    /// Darwin also reports a paused child (`CLD_STOPPED`, for example after `SIGSTOP` or a
    /// debugger attach) to `WEXITED`. Such a child is alive: it keeps its record and its lock, and
    /// a stop must still signal it. Only `CLD_EXITED`, `CLD_KILLED`, and `CLD_DUMPED` are ends.
    static func state(code: Int32, status: Int32) -> ProcessState {
        switch code {
        case CLD_EXITED: .exited(status: status)
        case CLD_KILLED, CLD_DUMPED: .signalled(signal: status)
        default: .running
        }
    }

    /// Reaps an exited child. Call only after `peek` reported an exit, so it never blocks.
    static func reap(_ pid: pid_t) {
        var status: Int32 = 0
        while waitpid(pid, &status, WNOHANG) < 0, errno == EINTR {}
    }
}

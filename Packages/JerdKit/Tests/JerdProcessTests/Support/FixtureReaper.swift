import Darwin
import Foundation

/// Finds the fixture processes that a test left running in its temporary folder and ends them.
///
/// Every fixture starts with its working folder inside the test's temporary folder, and its
/// children inherit it. A test that throws before its Stop (for example a `#require` or a start
/// that timed out under load) would otherwise leave a fixture that ignores SIGTERM running for hours.
/// A copy of the reaper in `JerdServiceKitTestSupport`, which these lower-layer tests cannot import.
enum FixtureReaper {
    /// Waits up to `grace` for the processes whose working folder is inside `folder` to end, then
    /// sends SIGKILL to each one that is still running. Only processes of this user are found.
    /// - Returns: the PIDs that outlived the grace period. A passing test returns none.
    static func reap(in folder: URL, grace: Duration = .seconds(5)) -> [pid_t] {
        guard let root = realPath(folder.path) else { return [] }
        let deadline = ContinuousClock.now + grace
        var survivors = processes(in: root)
        while !survivors.isEmpty, ContinuousClock.now < deadline {
            usleep(10_000)
            survivors = processes(in: root)
        }
        for pid in survivors { kill(pid, SIGKILL) }
        return survivors
    }

    /// The PIDs of this user's processes, other than this one, whose working folder is in `root`.
    static func processes(in root: String) -> [pid_t] {
        let capacity = proc_listallpids(nil, 0) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return pids.prefix(Int(max(count, 0))).filter { pid in
            guard pid > 0, pid != getpid(), let folder = workingFolder(of: pid) else { return false }
            return folder == root || folder.hasPrefix(root + "/")
        }
    }

    private static func workingFolder(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

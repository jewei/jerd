import Darwin

/// nil means inspection failed or was incomplete; only [] proves an empty group.
struct ProcessGroupInspector: Sendable {
    typealias List = @Sendable (pid_t, UnsafeMutableBufferPointer<pid_t>) -> (count: Int32, error: Int32)
    private let list: List

    init(list: @escaping List = Self.nativeList) { self.list = list }

    func liveMembers(of group: pid_t) -> [pid_t]? {
        var pids = [pid_t](repeating: 0, count: 4096)
        // A full buffer may omit members. Repeated interruption is also unknown.
        for _ in 0..<3 {
            let result = pids.withUnsafeMutableBufferPointer { list(group, $0) }
            if result.error == EINTR { continue }
            guard result.error == 0, result.count >= 0, result.count < pids.count else { return nil }
            var live: [pid_t] = []
            for pid in pids.prefix(Int(result.count)) {
                guard pid > 1, let running = Self.isLive(pid) else { return nil }
                if running { live.append(pid) }
            }
            return live
        }
        return nil
    }

    static func nativeList(_ group: pid_t, _ pids: UnsafeMutableBufferPointer<pid_t>) -> (count: Int32, error: Int32) {
        // libproc returns zero on failure as well as for an empty group.
        errno = 0
        let count = proc_listpgrppids(group, pids.baseAddress, Int32(pids.count * MemoryLayout<pid_t>.size))
        let error = errno
        return (count, error)
    }

    private static func isLive(_ pid: pid_t) -> Bool? {
        for _ in 0..<3 {
            var info = proc_bsdinfo()
            errno = 0
            let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
            let error = errno
            if size == MemoryLayout.size(ofValue: info), error == 0 { return info.pbi_status != SZOMB }
            if size == 0, error == ESRCH { return false } // Exited since enumeration.
            if error != EINTR { return nil }
        }
        return nil
    }
}

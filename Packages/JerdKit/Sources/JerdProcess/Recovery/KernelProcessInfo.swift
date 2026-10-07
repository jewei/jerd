import Darwin

/// Thin wrappers around the kernel calls that describe one process and the system start.
enum KernelProcessInfo {
    /// The BSD information of `pid`, with the `errno` of the call. `errno` is cleared first.
    static func bsdInfo(_ pid: pid_t) -> (info: proc_bsdinfo?, error: Int32) {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        let error = errno
        return (result == size ? info : nil, error)
    }

    /// The executable path of `pid`, or nil.
    static func executablePath(_ pid: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// `kern.boottime` seconds, or nil.
    static func bootSeconds() -> Int64? {
        var boot = timeval()
        var length = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &length, nil, 0) == 0 else { return nil }
        return Int64(boot.tv_sec)
    }

    /// `kern.bootsessionuuid`, or nil.
    static func bootSessionID() -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = buffer.count
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &length, nil, 0) == 0 else { return nil }
        let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// The 8 words of the audit token of `pid`, or nil when the task port is not available.
    static func auditWords(_ pid: pid_t) -> [UInt32]? {
        var port: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &port) == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, port) }
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &token) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(port, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return withUnsafeBytes(of: token) { Array($0.bindMemory(to: UInt32.self)) }
    }

    /// True only when `kill(pid, 0)` proves that no such process exists (`ESRCH`).
    static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) < 0 && errno == ESRCH
    }
}

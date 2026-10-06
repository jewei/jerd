import Darwin

/// Reads executables with `proc_pidpath` and stops processes with `kill(pid, SIGTERM)`.
struct LiveProcessInspector: ProcessInspecting {
    func executablePath(of pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func terminate(_ pid: Int32) -> Bool {
        pid > 0 && kill(pid, SIGTERM) == 0
    }
}

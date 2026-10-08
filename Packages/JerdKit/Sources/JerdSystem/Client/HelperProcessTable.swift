import Darwin

/// The live helper process check: the kernel process table, without root. A regular user can read
/// the short BSD information of every process; the helper is the root process whose command name
/// is the helper executable name.
public struct HelperProcessTable: HelperProcessInspecting {
    /// The command name of the helper process: the last part of its bundle program path.
    static let commandName = String(HelperServiceIdentity.bundleProgram.split(separator: "/").last ?? "JerdHelper")

    public init() {}

    public func isHelperRunning() -> Bool {
        Self.processIDs().contains { Self.isHelper($0) }
    }

    static func processIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return count > 0 ? pids.prefix(Int(count)).filter { $0 > 0 } : []
    }

    /// True when `pid` is a root process named like the helper.
    static func isHelper(_ pid: pid_t, named name: String = commandName) -> Bool {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size, info.pbsi_uid == 0 else {
            return false
        }
        return command(of: info) == name
    }

    static func command(of info: proc_bsdshortinfo) -> String {
        withUnsafeBytes(of: info.pbsi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

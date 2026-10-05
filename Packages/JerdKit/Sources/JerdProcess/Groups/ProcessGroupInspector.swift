import Darwin

/// Lists the live (non-zombie) members of a process group, with an honest "unknown" answer.
public struct ProcessGroupInspector: Sendable {
    /// What an inspection proved about a group.
    public enum Membership: Equatable, Sendable {
        /// The group has no live member.
        case empty
        /// The live members (never empty).
        case members([pid_t])
        /// The inspection failed or was incomplete. Treat it as "members may remain".
        case unknown
    }

    /// Lists group members into the buffer. Returns the PID count and the `errno` after the call.
    public typealias List = @Sendable (pid_t, UnsafeMutableBufferPointer<pid_t>) -> (count: Int32, error: Int32)
    /// Reads the liveness of one PID: true (live), false (zombie or gone), or nil (unknown).
    public typealias Liveness = @Sendable (pid_t) -> Bool?

    /// The PID buffer size. A full buffer can hide members, so it means `unknown`.
    public static let capacity = 4_096
    /// The number of attempts when a call is interrupted (`EINTR`).
    public static let attempts = 3

    private let list: List
    private let liveness: Liveness

    public init(list: @escaping List = Self.systemList, liveness: @escaping Liveness = Self.systemLiveness) {
        self.list = list
        self.liveness = liveness
    }

    /// The live members of `group`.
    public func members(of group: pid_t) -> Membership {
        var pids = [pid_t](repeating: 0, count: Self.capacity)
        for _ in 0..<Self.attempts {
            let result = pids.withUnsafeMutableBufferPointer { list(group, $0) }
            if result.error == EINTR { continue }
            guard result.error == 0, result.count >= 0, result.count < Self.capacity else { return .unknown }
            var live: [pid_t] = []
            for pid in pids.prefix(Int(result.count)) {
                guard pid > 1, let isLive = liveness(pid) else { return .unknown }
                if isLive { live.append(pid) }
            }
            return live.isEmpty ? .empty : .members(live)
        }
        return .unknown
    }

    /// True unless the group is proven to have no live member other than `leader`.
    public func mayHaveMembers(otherThan leader: pid_t, in group: pid_t) -> Bool {
        switch members(of: group) {
        case .empty: false
        case .members(let pids): pids.contains { $0 != leader }
        case .unknown: true
        }
    }

    /// `proc_listpgrppids`. libproc returns 0 for both an empty group and a failure, so `errno`
    /// is cleared first and read after the call.
    public static let systemList: List = { group, buffer in
        errno = 0
        let count = proc_listpgrppids(group, buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        return (count, errno)
    }

    /// `proc_pidinfo(PROC_PIDTBSDINFO)`: a zombie or a vanished PID is not live; other errors are unknown.
    public static let systemLiveness: Liveness = { pid in
        for _ in 0..<attempts {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            errno = 0
            let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
            let error = errno
            if result == size, error == 0 { return info.pbi_status != SZOMB }
            if result == 0, error == ESRCH { return false }
            if error != EINTR { return nil }
        }
        return nil
    }
}

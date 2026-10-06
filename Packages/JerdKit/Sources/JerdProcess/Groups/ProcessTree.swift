import Darwin

/// Finds the live descendants of processes by their parent chain, also those that left the
/// process group with `setsid` or `setpgid`.
///
/// The parent chain exists only while each parent runs: when a parent exits, its children move to
/// `launchd`. So a walk finds an escaped process only while its parent still runs, and callers walk
/// before they signal a leader.
public struct ProcessTree: Sendable {
    /// One live process, named by its PID and its start time, so that a reused PID never matches.
    public struct Member: Hashable, Sendable {
        public let processID: pid_t
        public let groupID: pid_t
        public let startedSeconds: UInt64
        public let startedMicroseconds: UInt64

        public init(processID: pid_t, groupID: pid_t, startedSeconds: UInt64, startedMicroseconds: UInt64) {
            self.processID = processID
            self.groupID = groupID
            self.startedSeconds = startedSeconds
            self.startedMicroseconds = startedMicroseconds
        }

        /// True when `other` is the same process (same PID and start time).
        public func isSameProcess(as other: Member) -> Bool {
            processID == other.processID && startedSeconds == other.startedSeconds
                && startedMicroseconds == other.startedMicroseconds
        }
    }

    /// What an inspection of one PID proved.
    public enum Lookup: Equatable, Sendable {
        /// The PID names a live process.
        case live(Member)
        /// The PID is gone or a zombie.
        case gone
        /// The inspection failed. Treat it as "may be live".
        case unknown
    }

    /// The child PIDs of a PID (zombies included), or nil when the list failed.
    public typealias Children = @Sendable (pid_t) -> [pid_t]?
    /// Inspects one PID.
    public typealias Inspect = @Sendable (pid_t) -> Lookup

    /// The most processes that one walk visits. A larger tree is reported as unknown.
    public static let capacity = 4_096

    private let children: Children
    private let inspect: Inspect

    public init(children: @escaping Children = Self.systemChildren, inspect: @escaping Inspect = Self.systemInspect) {
        self.children = children
        self.inspect = inspect
    }

    /// The live descendants of `roots` (the roots themselves excluded), or nil when a list failed
    /// or the tree is too large. Nil means "descendants may exist".
    public func descendants(of roots: [pid_t]) -> [Member]? {
        var visited = Set(roots)
        var pending = roots
        var found: [Member] = []
        while let parent = pending.popLast() {
            guard let pids = children(parent) else { return nil }
            for pid in pids where pid > 1 && visited.insert(pid).inserted {
                guard visited.count <= Self.capacity else { return nil }
                pending.append(pid)
                switch inspect(pid) {
                case .live(let member): found.append(member)
                case .gone: continue
                case .unknown: return nil
                }
            }
        }
        return found.sorted { $0.processID < $1.processID }
    }

    /// The current state of `member`: `.live` with its current group, `.gone` when it exited or its
    /// PID now names another process, or `.unknown`.
    public func current(_ member: Member) -> Lookup {
        switch inspect(member.processID) {
        case .live(let now): now.isSameProcess(as: member) ? .live(now) : .gone
        case .gone: .gone
        case .unknown: .unknown
        }
    }

    /// `proc_listchildpids`. libproc returns 0 for both "no child" and a failure, so `errno` is
    /// cleared first and read after the call.
    public static let systemChildren: Children = { parent in
        var pids = [pid_t](repeating: 0, count: capacity)
        for _ in 0..<ProcessGroupInspector.attempts {
            errno = 0
            let count = proc_listchildpids(parent, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            let error = errno
            if error == EINTR { continue }
            guard error == 0, count >= 0, count < capacity else { return nil }
            return Array(pids.prefix(Int(count)))
        }
        return nil
    }

    /// `proc_pidinfo(PROC_PIDTBSDINFO)`: a zombie or a vanished PID is gone; other errors are unknown.
    public static let systemInspect: Inspect = { pid in
        for _ in 0..<ProcessGroupInspector.attempts {
            let (info, error) = KernelProcessInfo.bsdInfo(pid)
            if let info {
                guard info.pbi_status != SZOMB else { return .gone }
                return .live(
                    Member(
                        processID: pid, groupID: pid_t(info.pbi_pgid), startedSeconds: info.pbi_start_tvsec,
                        startedMicroseconds: info.pbi_start_tvusec))
            }
            if error == ESRCH { return .gone }
            if error != EINTR { return .unknown }
        }
        return .unknown
    }
}

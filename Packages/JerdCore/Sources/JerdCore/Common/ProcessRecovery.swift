import Foundation
import Darwin

/// The audit token includes the kernel's PID generation. Signals use that token,
/// never a saved PID alone. Boot and start times also protect persisted records.
struct ProcessIdentity: Codable, Equatable, Sendable {
    let processID: Int32
    let userID: UInt32
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64
    let bootSeconds: Int64
    let executable: String
    let auditWords: [UInt32]?

    enum Match: Equatable { case running, exited, replaced, unknown }

    static func capture(_ pid: Int32) throws -> Self {
        var info = proc_bsdinfo()
        guard pid > 1, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info),
              info.pbi_status != SZOMB else { throw JerdError.unavailable("The process is no longer available for inspection.") }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else {
            throw JerdError.unavailable("Cannot inspect the process executable. No process was signalled.")
        }
        var boot = timeval(), length = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &length, nil, 0) == 0 else {
            throw JerdError.unavailable("Cannot inspect the system start time.")
        }
        let words = auditToken(pid)
        // The process can exit or exec while its path and token are read.
        var after = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, Int32(MemoryLayout.size(ofValue: after))) == MemoryLayout.size(ofValue: after),
              info.pbi_start_tvsec == after.pbi_start_tvsec, info.pbi_start_tvusec == after.pbi_start_tvusec,
              info.pbi_uid == after.pbi_uid else { throw JerdError.unavailable("The process changed during inspection.") }
        return Self(processID: pid, userID: info.pbi_uid, startedSeconds: info.pbi_start_tvsec,
                    startedMicroseconds: info.pbi_start_tvusec, bootSeconds: Int64(boot.tv_sec),
                    executable: String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), auditWords: words)
    }

    func match() -> Match {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(processID, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info)))
        if size == 0, errno == ESRCH { return .exited }
        if size == MemoryLayout.size(ofValue: info), info.pbi_status == SZOMB { return .exited }
        guard let current = try? Self.capture(processID) else { return .unknown }
        guard current.userID == userID, current.startedSeconds == startedSeconds,
              current.startedMicroseconds == startedMicroseconds, current.bootSeconds == bootSeconds else { return .replaced }
        // A changed executable or lost audit permission is uncertain, not a stale record.
        guard current.executable == executable, current.auditWords == auditWords else { return .unknown }
        return .running
    }

    static var supportsAuditedSignals: Bool {
        guard let library = dlopen(nil, RTLD_LAZY) else { return false }
        defer { dlclose(library) }
        return dlsym(library, "proc_signal_with_audittoken") != nil
    }

    func signalGracefully(_ signal: Int32) throws {
        guard [SIGTERM, SIGQUIT, SIGINT].contains(signal), userID == geteuid(), processID != getpid(),
              match() == .running, let words = auditWords, words.count == 8 else {
            throw JerdError.unavailable("Process ownership cannot be verified. No process was signalled.")
        }
        // Resolve at runtime so older supported systems fail safely if the API is absent.
        guard let library = dlopen(nil, RTLD_LAZY) else { throw JerdError.unavailable("Safe process signalling is unavailable.") }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "proc_signal_with_audittoken") else {
            throw JerdError.unavailable("This macOS version cannot safely signal a saved process. Stop the verified service manually.")
        }
        typealias Signal = @convention(c) (UnsafeMutablePointer<audit_token_t>, Int32) -> Int32
        let send = unsafeBitCast(symbol, to: Signal.self)
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { $0.copyBytes(from: words.withUnsafeBytes { Data($0) }) }
        let result = send(&token, signal)
        guard result == 0 || result == ESRCH else { throw JerdError.process("The saved process could not stop safely (\(result)). Its record was preserved.") }
    }

    private static func auditToken(_ pid: Int32) -> [UInt32]? {
        var port: mach_port_name_t = 0
        guard task_name_for_pid(mach_task_self_, pid, &port) == KERN_SUCCESS else { return nil }
        defer { mach_port_deallocate(mach_task_self_, port) }
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(port, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return withUnsafeBytes(of: token) { Array($0.bindMemory(to: UInt32.self)) }
    }
}

struct PreviousProcessRun: Codable, Sendable {
    private static let maximumBytes = 131_072
    private static let maximumDescendants = 1024
    let processID: Int32
    let runtimeID: String
    let identity: ProcessIdentity?
    let controller: ProcessIdentity?
    let gracefulSignal: Int32?
    var descendants: [ProcessIdentity]?

    static func record(_ pid: Int32, runtimeID: String, at file: URL, signal: Int32 = SIGTERM) throws {
        let controller = try ProcessIdentity.capture(getpid())
        let identity: ProcessIdentity
        do { identity = try ProcessIdentity.capture(pid) }
        catch {
            // A fast-exiting master can leave a live child. Persist conservative
            // evidence before reporting failure; a saved PID alone is never signalled.
            if !PrivateFiles.exists(file) {
                let fallback = Self(processID: pid, runtimeID: runtimeID, identity: nil,
                    controller: controller, gracefulSignal: signal)
                try PrivateFiles.write(JSONEncoder().encode(fallback), to: file)
            }
            throw error
        }
        guard identity.userID == geteuid() else { throw JerdError.invalid("The process belongs to another user.") }
        let record = Self(processID: pid, runtimeID: runtimeID, identity: identity,
                          controller: controller, gracefulSignal: signal)
        try PrivateFiles.write(JSONEncoder().encode(record), to: file)
    }

    static func read(_ file: URL) throws -> Self {
        let data = try PrivateFiles.read(file, limit: maximumBytes)
        let record = try JSONDecoder().decode(Self.self, from: data)
        guard record.processID > 1, record.identity == nil || record.identity?.processID == record.processID,
              record.descendants?.count ?? 0 <= maximumDescendants else { throw JerdError.corruptConfiguration("The saved process record is invalid. It was preserved.") }
        return record
    }

    /// Preserve the previous readable record if all verified children cannot fit.
    /// Recovery must finish this write before it sends any signal.
    func writeRecovery(to file: URL) throws {
        guard descendants?.count ?? 0 <= Self.maximumDescendants else {
            throw JerdError.unavailable("Too many service processes to save for recovery. The previous record was preserved. No process was signalled.")
        }
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else {
            throw JerdError.unavailable("The service recovery record is too large. The previous record was preserved. No process was signalled.")
        }
        try PrivateFiles.write(data, to: file)
    }

    /// Called while the service's exclusive lock is held. Legacy live PIDs stay blocked.
    static func requireStopped(at file: URL, processGroups: ProcessGroupInspector = .init()) throws {
        guard PrivateFiles.exists(file) else { return }
        let record = try read(file)
        if record.isStale(using: processGroups) {
            try FileManager.default.removeItem(at: file)
            return
        }
        throw JerdError.unavailable("A previous service process needs inspection (PID \(record.processID)). Open Advanced → Process recovery. No process was signalled.")
    }

    /// A reaped leader can still have live group members. Never clear their
    /// record merely because the leader exited. PID replacement proves the old
    /// group ID was released; saved descendants are checked separately.
    var isStale: Bool { isStale(using: .init()) }

    func isStale(using processGroups: ProcessGroupInspector) -> Bool {
        if let identity {
            let master = identity.match()
            guard [.exited, .replaced].contains(master),
                  (descendants ?? []).allSatisfy({ [.exited, .replaced].contains($0.match()) }) else { return false }
            return master == .replaced || processGroups.liveMembers(of: processID) == []
        }
        return kill(processID, 0) < 0 && errno == ESRCH && processGroups.liveMembers(of: processID) == []
    }

    func hasUnverifiedGroupMembers(using processGroups: ProcessGroupInspector) -> Bool {
        guard identity?.match() != .replaced, let pids = processGroups.liveMembers(of: processID) else { return identity?.match() != .replaced }
        let members = (identity.map { [$0] } ?? []) + (descendants ?? [])
        return pids.contains { pid in !members.contains { $0.processID == pid && $0.match() == .running } }
    }

}

public struct ProcessRecoveryFinding: Identifiable, Sendable {
    public enum State: Sendable { case stale, recoverable, managed, manual }
    public let id: String
    public let title: String
    public let detail: String
    public let state: State
    public var canRecover: Bool { state == .stale || state == .recoverable }
}

/// Inspects fixed Jerd record locations. Recovery never accepts a caller's PID,
/// executable, signal, or arbitrary data path.
public actor ProcessRecoveryStore {
    private let directory: URL
    private let processGroups: ProcessGroupInspector
    private var busy = false
    public init(directory: URL) { self.directory = directory; processGroups = .init() }
    init(directory: URL, processGroups: ProcessGroupInspector) { self.directory = directory; self.processGroups = processGroups }

    public func inspect() throws -> [ProcessRecoveryFinding] {
        try records().map { id, file in
            do { return finding(id: id, record: try PreviousProcessRun.read(file)) }
            catch { return ProcessRecoveryFinding(id: id, title: id, detail: error.localizedDescription, state: .manual) }
        }
    }

    public func recover(_ id: String, timeout: Duration = .seconds(30)) async throws {
        guard !busy else { throw JerdError.unavailable("Wait for process recovery to finish.") }
        busy = true; defer { busy = false }
        guard let file = try records()[id] else { throw JerdError.unavailable("The process record is no longer present. Inspect again.") }
        let root = file.deletingLastPathComponent()
        let lockName = id.hasPrefix("Web/") ? "recovery.lock" : "service.lock"
        let descriptor = open(root.appendingPathComponent(lockName).path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw JerdError.unavailable("Cannot lock the saved service.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw JerdError.unavailable("Another Jerd process is using this service.") }
        defer { _ = flock(descriptor, LOCK_UN) }
        var record = try PreviousProcessRun.read(file)
        let status = finding(id: id, record: record)
        guard status.canRecover else { throw JerdError.unavailable(status.detail) }
        if !record.isStale(using: processGroups) {
            guard let identity = record.identity else { throw JerdError.unavailable("The old record has no verified process identity. Use manual recovery.") }
            if identity.match() == .running {
                // Retain exact descendant identities before signalling the master.
                // A second recovery attempt can finish if the app exits mid-stop.
                var members = record.descendants ?? []
                guard let pids = processGroups.liveMembers(of: record.processID) else {
                    throw JerdError.unavailable("Cannot inspect all service processes. No process was signalled.")
                }
                for pid in pids where pid != record.processID {
                    let child: ProcessIdentity
                    do { child = try ProcessIdentity.capture(pid) }
                    catch {
                        if kill(pid, 0) < 0, errno == ESRCH { continue }
                        throw JerdError.unavailable("A service child cannot be verified. No process was signalled.")
                    }
                    guard child.userID == identity.userID, child.auditWords != nil else {
                        throw JerdError.unavailable("A service child cannot be verified. No process was signalled.")
                    }
                    if !members.contains(child) { members.append(child) }
                }
                record.descendants = members
                try record.writeRecovery(to: file)
                try identity.signalGracefully(record.gracefulSignal ?? SIGTERM)
            } else {
                for member in record.descendants ?? [] where member.match() == .running {
                    try member.signalGracefully(SIGTERM)
                }
            }
            let deadline = ContinuousClock.now + timeout
            while !record.isStale(using: processGroups), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            // Never escalate to SIGKILL, including for data-service descendants.
            guard record.isStale(using: processGroups) else {
                throw JerdError.unavailable("The service has not stopped safely. Its process record and data were preserved. Retry recovery after checking its log.")
            }
        }
        try FileManager.default.removeItem(at: file)
    }

    private func finding(id: String, record: PreviousProcessRun) -> ProcessRecoveryFinding {
        if record.isStale(using: processGroups) {
            return .init(id: id, title: id, detail: "The saved process has exited or its PID was reused. Clear this stale record to retry Start.", state: .stale)
        }
        guard let controller = record.controller, let identity = record.identity else {
            return .init(id: id, title: id, detail: "Legacy process record for PID \(record.processID). Ownership cannot be proved. Inspect its executable and stop the service manually; Jerd will not signal this PID.", state: .manual)
        }
        if controller.match() == .running {
            return .init(id: id, title: id, detail: "A running Jerd session manages PID \(record.processID). Use its normal Stop control.", state: .managed)
        }
        guard [.exited, .replaced].contains(controller.match()), identity.userID == geteuid(),
              ProcessIdentity.supportsAuditedSignals, identity.auditWords != nil, identity.match() != .unknown,
              (record.descendants ?? []).allSatisfy({ $0.match() != .unknown }),
              identity.match() == .running || !record.hasUnverifiedGroupMembers(using: processGroups) else {
            return .init(id: id, title: id, detail: "Ownership of PID \(record.processID) is uncertain. The record and data were preserved. Inspect this service manually.", state: .manual)
        }
        return .init(id: id, title: id, detail: "\(record.runtimeID) · PID \(record.processID)\n\(identity.executable)\nThe previous Jerd session ended. Request a graceful stop, then retry Start.", state: .recoverable)
    }

    private func records() throws -> [String: URL] {
        var result: [String: URL] = [:]
        for service in ["mail", "storage"] {
            let root = directory.appendingPathComponent(service)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            try PrivateFiles.requireDirectory(root, within: directory)
            let file = root.appendingPathComponent("active-run.json")
            if PrivateFiles.exists(file) { result[service.capitalized] = file }
        }
        for (folder, prefix, nested) in [("databases/instances", "Database", true), ("tunnels/instances", "Tunnel", true), ("environment/processes", "Web", false)] {
            let root = directory.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            try PrivateFiles.requireDirectory(root, within: directory)
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw JerdError.invalid("The process record directory is invalid.") }
            for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                let name = nested ? child.lastPathComponent : child.deletingPathExtension().lastPathComponent
                guard UUID(uuidString: name) != nil, try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
                if nested { try PrivateFiles.requireDirectory(child, within: directory) }
                else if child.pathExtension != "json" { continue }
                let file = nested ? child.appendingPathComponent("active-run.json") : child
                if PrivateFiles.exists(file) { result["\(prefix)/\(name)"] = file }
            }
        }
        return result
    }
}

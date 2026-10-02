import Foundation
import Darwin

public struct ProcessRequest: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let directory: URL
    public let environment: [String: String]
    public let listeningSockets: ListeningSockets?
    public init(executable: URL, arguments: [String], directory: URL, environment: [String: String] = [:],
                listeningSockets: ListeningSockets? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.listeningSockets = listeningSockets
    }
}

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public let diagnosticOutput: String
    public init(status: Int32, output: String, diagnosticOutput: String? = nil) {
        self.status = status; self.output = output; self.diagnosticOutput = diagnosticOutput ?? output
    }
}

public protocol CommandRunning: Sendable {
    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult
}

public protocol ProcessControlling: Sendable {
    func start(_ request: ProcessRequest, log: URL) async throws -> UUID
    func isRunning(_ id: UUID) async -> Bool
    func processIdentifier(_ id: UUID) async -> Int32?
    func stop(_ id: UUID, gracefulSignal: Int32) async
    func stopAll() async
}

/// Each child leads a new process group. Keep exited leaders unreaped until cleanup,
/// so their IDs cannot be reused while a group signal is still possible.
public actor ProcessSupervisor: ProcessControlling {
    private var children: [UUID: pid_t] = [:]
    private var stopping: Set<UUID> = []
    private var logs: [UUID: URL] = [:]
    private var logMaintenance: Task<Void, Never>?
    private let logPrefixBytes: Int
    private let gracefulTimeout: Duration
    private let processGroups: ProcessGroupInspector
    public init() { logPrefixBytes = 0; gracefulTimeout = .seconds(30); processGroups = .init() }
    init(logPrefixBytes: Int) { self.logPrefixBytes = logPrefixBytes; gracefulTimeout = .seconds(30); processGroups = .init() }
    init(gracefulTimeout: Duration, processGroups: ProcessGroupInspector = .init()) {
        self.gracefulTimeout = gracefulTimeout; logPrefixBytes = 0; self.processGroups = processGroups
    }

    public func start(_ request: ProcessRequest, log: URL) throws -> UUID {
        guard geteuid() != 0 else { throw JerdError.process("Jerd cannot run runtime processes as root.") }
        guard request.executable.isFileURL,
              FileManager.default.isExecutableFile(atPath: request.executable.path) else {
            throw JerdError.process("Executable is missing or is not executable: \(request.executable.path)")
        }
        let environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8",
                           "HOME": request.directory.path].merging(request.environment) { _, new in new }
        let arguments = [request.executable.path] + request.arguments
        let environmentStrings = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        guard (arguments + environmentStrings + [request.directory.path]).allSatisfy({ !$0.contains("\0") }) else {
            throw JerdError.process("Process arguments cannot contain NUL characters.")
        }
        try PrivateFiles.write(Data(), to: log)
        let descriptor = open(log.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw JerdError.process("Cannot open process log: \(log.path)") }
        defer { close(descriptor) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try checked(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try checked(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT |
                                                               POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)))
        try checked(posix_spawnattr_setpgroup(&attributes, 0))
        var mask = sigset_t()
        sigemptyset(&mask)
        try checked(posix_spawnattr_setsigmask(&attributes, &mask))
        sigfillset(&mask)
        try checked(posix_spawnattr_setsigdefault(&attributes, &mask))
        try checked(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try checked(posix_spawn_file_actions_adddup2(&actions, descriptor, STDOUT_FILENO))
        try checked(posix_spawn_file_actions_adddup2(&actions, descriptor, STDERR_FILENO))
        try checked(posix_spawn_file_actions_addchdir_np(&actions, request.directory.path))
        var duplicates: [Int32] = []
        defer { duplicates.forEach { Darwin.close($0) } }
        if let sockets = request.listeningSockets {
            _ = try sockets.ports()
            // Duplicate above the destination range before any child file action
            // can overwrite a source descriptor. The parent retains ownership.
            for (source, target) in [(sockets.http, Int32(3)), (sockets.https, Int32(4))] {
                let duplicate = fcntl(source.fileDescriptor, F_DUPFD_CLOEXEC, 64)
                guard duplicate >= 0 else { throw JerdError.process("Cannot pass the loopback listener to Caddy.") }
                duplicates.append(duplicate)
                try checked(posix_spawn_file_actions_adddup2(&actions, duplicate, target))
            }
        }
        var argv = arguments.map { strdup($0) } + [nil]
        var envp = environmentStrings.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else {
            throw JerdError.process("Cannot allocate process arguments.")
        }
        var pid: pid_t = 0
        let result = argv.withUnsafeMutableBufferPointer { args in
            envp.withUnsafeMutableBufferPointer { env in
                posix_spawn(&pid, request.executable.path, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        try checked(result)
        let id = UUID()
        children[id] = pid
        logs[id] = log
        if logMaintenance == nil {
            logMaintenance = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, let self else { return }
                    await self.trimLogs()
                }
            }
        }
        return id
    }

    public func isRunning(_ id: UUID) -> Bool {
        guard let pid = children[id] else { return false }
        return status(pid) == nil
    }

    public func processIdentifier(_ id: UUID) -> Int32? {
        guard let pid = children[id], status(pid) == nil else { return nil }
        return pid
    }

    /// An exited, unreaped master still reserves its process group. Managers
    /// must retain that ownership until every child has stopped safely.
    func ownedProcessIdentifier(_ id: UUID) -> Int32? {
        guard let pid = children[id] else { return nil }
        var info = siginfo_t(), result: Int32
        repeat { result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) } while result < 0 && errno == EINTR
        return result == 0 ? pid : nil
    }

    public func exitStatus(_ id: UUID) -> Int32? {
        guard let pid = children[id] else { return nil }
        return status(pid)
    }

    public func stop(_ id: UUID, gracefulSignal: Int32 = SIGTERM) async {
        guard let pid = children[id] else { return }
        if stopping.contains(id) {
            await waitUntilStopped(id)
            return
        }
        stopping.insert(id)
        // If an external reaper took this child, do not signal its former ID.
        var ownership = siginfo_t()
        var ownershipResult: Int32
        repeat { ownershipResult = waitid(P_PID, id_t(pid), &ownership, WEXITED | WNOHANG | WNOWAIT) } while ownershipResult < 0 && errno == EINTR
        guard ownershipResult == 0 else {
            children[id] = nil
            finishLog(id)
            stopping.remove(id)
            return
        }
        if status(pid) == nil { _ = kill(pid, gracefulSignal) }
        await waitForExit(pid, seconds: 3)
        // Signal only the group created by this supervisor. The unreaped leader
        // reserves the group ID, including after an unexpected master exit.
        _ = kill(-pid, SIGTERM)
        await waitForGroup(pid, seconds: 2)
        _ = kill(-pid, SIGKILL)
        await waitForExit(pid)
        var rawStatus: Int32 = 0
        while waitpid(pid, &rawStatus, 0) < 0 && errno == EINTR {}
        children[id] = nil
        finishLog(id)
        stopping.remove(id)
    }

    /// Database shutdown must not escalate to SIGKILL. A timeout retains the
    /// owned child so the caller can report it and retry without losing data.
    public func stopGracefully(_ id: UUID, signal: Int32 = SIGTERM, timeout: Duration? = nil) async -> Bool {
        guard let pid = children[id] else { return true }
        if stopping.contains(id) {
            await waitUntilStopped(id)
            return children[id] == nil
        }
        stopping.insert(id)
        defer { stopping.remove(id) }
        var ownership = siginfo_t()
        var result: Int32
        repeat { result = waitid(P_PID, id_t(pid), &ownership, WEXITED | WNOHANG | WNOWAIT) } while result < 0 && errno == EINTR
        guard result == 0 else {
            children[id] = nil
            finishLog(id)
            return false
        }
        if status(pid) == nil { _ = kill(pid, signal) }
        let deadline = ContinuousClock.now + (timeout ?? gracefulTimeout)
        await waitForExit(pid, deadline: deadline)
        guard status(pid) != nil else { return false }
        if hasLiveDescendants(of: pid) { _ = kill(-pid, SIGTERM) }
        while hasLiveDescendants(of: pid), ContinuousClock.now < deadline {
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
        }
        guard !hasLiveDescendants(of: pid) else { return false }
        var rawStatus: Int32 = 0
        while waitpid(pid, &rawStatus, 0) < 0 && errno == EINTR {}
        children[id] = nil
        finishLog(id)
        return true
    }

    private func waitForGroup(_ pid: pid_t, seconds: Int) async {
        let deadline = ContinuousClock.now + .seconds(seconds)
        await Task.detached { [self] in
            while ContinuousClock.now < deadline {
                if await status(pid) != nil, await hasLiveDescendants(of: pid) == false { return }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }.value
    }

    private func hasLiveDescendants(of leader: pid_t) -> Bool {
        guard let pids = processGroups.liveMembers(of: leader) else { return true }
        return pids.contains { $0 != leader }
    }

    private func trimLogs() {
        for file in logs.values { try? ProcessLog.trim(file, prefixBytes: logPrefixBytes) }
    }

    private func finishLog(_ id: UUID) {
        if let file = logs.removeValue(forKey: id) { try? ProcessLog.trim(file, prefixBytes: logPrefixBytes) }
        if logs.isEmpty { logMaintenance?.cancel(); logMaintenance = nil }
    }

    private func waitForExit(_ pid: pid_t, seconds: Int) async {
        await waitForExit(pid, deadline: ContinuousClock.now + .seconds(seconds))
    }

    private func waitForExit(_ pid: pid_t, deadline: ContinuousClock.Instant? = nil) async {
        await Task.detached { [self] in
            while await status(pid) == nil {
                if let deadline, ContinuousClock.now >= deadline { return }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }.value
    }

    private func waitUntilStopped(_ id: UUID) async {
        await Task.detached { [self] in
            while await stopping.contains(id) {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }.value
    }

    private func status(_ pid: pid_t) -> Int32? {
        var info = siginfo_t()
        var result: Int32
        repeat { result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) } while result < 0 && errno == EINTR
        guard result == 0 else { return -1 }
        guard info.si_pid != 0 else { return nil }
        return info.si_code == CLD_EXITED ? info.si_status : 128 + info.si_status
    }

    private func checked(_ status: Int32) throws {
        guard status == 0 else { throw JerdError.process("Process operation failed: \(String(cString: strerror(status)))") }
    }

    public func stopAll() async {
        for id in Array(children.keys) { await stop(id) }
    }
}

public struct LocalCommandRunner: CommandRunning {
    public init() {}
    public func run(_ request: ProcessRequest, timeout: Duration = .seconds(15)) async throws -> CommandResult {
        // Each invocation owns its supervisor and files, including cancellation cleanup.
        let task = Task.detached {
            let supervisor = ProcessSupervisor(logPrefixBytes: 1_048_576)
            let log = request.directory.appendingPathComponent("command-\(UUID().uuidString).log")
            defer { try? FileManager.default.removeItem(at: log) }
            let id = try await supervisor.start(request, log: log)
            do {
                let deadline = ContinuousClock.now + timeout
                while await supervisor.isRunning(id), ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(25))
                }
                let timedOut = await supervisor.isRunning(id)
                let status = await supervisor.exitStatus(id)
                await supervisor.stopAll()
                let output = try ProcessLog.read(log)
                let tail = try ProcessLog.read(log, limit: 65_536, tail: true)
                guard !timedOut else { throw JerdError.process("Command timed out: \(request.executable.path)\n\(tail.suffix(4096))") }
                return CommandResult(status: status ?? -1, output: output, diagnosticOutput: tail)
            } catch {
                await supervisor.stopAll()
                throw error
            }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

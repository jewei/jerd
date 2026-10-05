import Darwin
import Foundation
import JerdFoundation

/// Starts a `SpawnPlan` with `posix_spawn`: a new process group, an empty signal mask, every
/// signal at its default action, and only the planned descriptors (close-on-exec by default).
enum Spawner {
    /// Spawns the plan and returns the child PID, which is also its process group ID.
    /// - Parameters:
    ///   - output: the descriptor for standard output and standard error.
    ///   - listeners: the listeners for descriptors 3 and 4, required when the plan uses them.
    static func spawn(_ plan: SpawnPlan, output: Int32, listeners: InheritedListeners?) throws -> pid_t {
        try requireSpawnable(plan, listeners: listeners)
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try configure(&attributes)
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        let duplicates = try addDescriptors(plan, output: output, listeners: listeners, to: &actions)
        defer { duplicates.forEach { close($0) } }
        try check(posix_spawn_file_actions_addchdir_np(&actions, plan.workingDirectory))
        return try withCStrings(plan.arguments) { argv in
            try withCStrings(plan.environment) { envp in
                var pid: pid_t = 0
                try check(posix_spawn(&pid, plan.executablePath, &actions, &attributes, argv, envp))
                return pid
            }
        }
    }

    /// The checks that run before any file is created: never as root, an executable file, valid listeners.
    static func requireSpawnable(
        _ plan: SpawnPlan, listeners: InheritedListeners?, effectiveUserID: uid_t = geteuid()
    ) throws {
        guard effectiveUserID != 0 else { throw JerdError.processFailed("Jerd cannot run runtime processes as root.") }
        guard FileManager.default.isExecutableFile(atPath: plan.executablePath) else {
            throw JerdError.processFailed("Executable is missing or is not executable: \(plan.executablePath)")
        }
        try listeners?.validate()
    }

    private static func configure(_ attributes: inout posix_spawnattr_t?) throws {
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        try check(posix_spawnattr_setflags(&attributes, Int16(flags)))
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var signals = sigset_t()
        sigemptyset(&signals)
        try check(posix_spawnattr_setsigmask(&attributes, &signals))
        sigfillset(&signals)
        try check(posix_spawnattr_setsigdefault(&attributes, &signals))
    }

    /// Adds the descriptor actions. Listener sources are first duplicated to 64 or above, so an
    /// earlier `dup2` cannot replace them. Returns the duplicates, which the caller closes.
    private static func addDescriptors(
        _ plan: SpawnPlan, output: Int32, listeners: InheritedListeners?, to actions: inout posix_spawn_file_actions_t?
    ) throws -> [Int32] {
        var duplicates: [Int32] = []
        do {
            for action in plan.descriptors {
                switch action.source {
                case .nullDevice:
                    try check(posix_spawn_file_actions_addopen(&actions, action.target, "/dev/null", O_RDONLY, 0))
                case .output:
                    try check(posix_spawn_file_actions_adddup2(&actions, output, action.target))
                case .httpListener, .httpsListener:
                    let source = try listenerDescriptor(action.source, listeners)
                    let duplicate = fcntl(source, F_DUPFD_CLOEXEC, 64)
                    guard duplicate >= 0 else { throw JerdError.processFailed("Cannot pass the loopback listener.") }
                    duplicates.append(duplicate)
                    try check(posix_spawn_file_actions_adddup2(&actions, duplicate, action.target))
                }
            }
            return duplicates
        } catch {
            duplicates.forEach { close($0) }
            throw error
        }
    }

    private static func listenerDescriptor(
        _ source: SpawnPlan.DescriptorSource, _ listeners: InheritedListeners?
    )
        throws -> Int32
    {
        guard let listeners else { throw JerdError.processFailed("Cannot pass the loopback listener.") }
        return source == .httpListener ? listeners.http.fileDescriptor : listeners.https.fileDescriptor
    }

    private static func withCStrings<Result>(
        _ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) throws -> Result
    ) throws -> Result {
        var pointers = strings.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        guard pointers.allSatisfy({ $0 != nil }) else {
            throw JerdError.processFailed("Cannot allocate process arguments.")
        }
        pointers.append(nil)
        return try pointers.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else {
                throw JerdError.processFailed("Cannot allocate process arguments.")
            }
            return try body(base)
        }
    }

    private static func check(_ status: Int32) throws {
        guard status == 0 else {
            throw JerdError.processFailed("Process operation failed: \(SystemError.describe(status))")
        }
    }
}

import Darwin
import Foundation

/// Starts one child with `posix_spawn` as the leader of a new process group. A time-out or an
/// interrupt then reaches the child and every process that it starts, for example the test runner
/// of `swift test` or the compilers of `xcodebuild`.
enum ChildProcess {
    /// Starts the command. The child gets `/dev/null` as standard input, the two given descriptors as
    /// standard output and standard error, default signal actions, and no other open descriptor.
    static func spawn(_ invocation: Invocation, standardOutput: Int32, standardError: Int32) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, standardOutput, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, standardError, STDERR_FILENO)
        if let workingDirectory = invocation.workingDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path)
        }
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        configure(&attributes)
        let arguments = [invocation.executable.path] + invocation.arguments
        let environment = (invocation.environment ?? ProcessInfo.processInfo.environment).map {
            "\($0.key)=\($0.value)"
        }
        var processIdentifier: pid_t = 0
        let status = withCStrings(arguments) { argv in
            withCStrings(environment) { envp in
                posix_spawn(&processIdentifier, invocation.executable.path, &actions, &attributes, argv, envp)
            }
        }
        guard status == 0 else {
            throw InvocationFailure.launchFailed(
                commandLine: invocation.commandLine, reason: String(cString: strerror(status)))
        }
        return processIdentifier
    }

    /// A new process group, an empty signal mask, and default actions for every signal. `./dev` itself
    /// ignores SIGINT, SIGTERM, and SIGHUP to forward them, and an ignored signal would stay ignored in
    /// the child without SIGDEF.
    private static func configure(_ attributes: inout posix_spawnattr_t?) {
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var everySignal = sigset_t(UInt32.max)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        var noSignal = sigset_t(0)
        posix_spawnattr_setsigmask(&attributes, &noSignal)
    }

    /// Waits on a new thread until the child exits and reports its shell-style status. It does not
    /// reap the child: the zombie keeps the process group ID reserved until `reap` runs.
    static func waitForExit(_ processIdentifier: pid_t, report: @escaping @Sendable (Int32) -> Void) {
        let thread = Thread { report(exitStatus(waitingFor: processIdentifier)) }
        thread.name = "jerd-dev wait \(processIdentifier)"
        thread.start()
    }

    /// The exit status as a shell reports it: 128 plus the signal number for a signal.
    static func exitStatus(waitingFor processIdentifier: pid_t) -> Int32 {
        var information = siginfo_t()
        while waitid(P_PID, id_t(processIdentifier), &information, WEXITED | WNOWAIT) != 0 {
            guard errno == EINTR else { return -1 }
        }
        return information.si_code == CLD_EXITED ? information.si_status : 128 + information.si_status
    }

    /// Removes the exited child from the process table.
    static func reap(_ processIdentifier: pid_t) {
        var status: Int32 = 0
        while waitpid(processIdentifier, &status, 0) == -1, errno == EINTR {}
    }

    /// Sends a signal to every process in the group that the child leads.
    static func signalGroup(_ processIdentifier: pid_t, _ signal: Int32) {
        kill(-processIdentifier, signal)
    }

    /// Passes a NULL-terminated array of C strings to `body` and frees the strings after it.
    private static func withCStrings<Result>(
        _ strings: [String],
        _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>?) -> Result
    ) -> Result {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress) }
    }
}

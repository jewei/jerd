import Darwin
import JerdFoundation

/// Sends a graceful signal to a saved process through its kernel audit token, never through a PID.
///
/// The audit token contains the PID version, so a reused PID cannot receive the signal.
public struct AuditedSignaller: Sendable {
    /// Sends `signal` to the process of an 8-word audit token. Returns 0 or an `errno` value.
    public typealias Send = @Sendable (_ auditWords: [UInt32], _ signal: Int32) -> Int32

    /// The only signals that recovery sends: graceful stops for Caddy, PHP-FPM, and data services.
    public static let allowedSignals: Set<Int32> = [SIGTERM, SIGQUIT, SIGINT]

    private let send: Send?
    private let match: @Sendable (ProcessIdentity) -> ProcessIdentity.Match

    /// - Parameters:
    ///   - send: the signal function, or nil when the system has none.
    ///   - match: verifies that the saved identity still runs.
    public init(send: Send?, match: @escaping @Sendable (ProcessIdentity) -> ProcessIdentity.Match) {
        self.send = send
        self.match = match
    }

    /// The system signaller: `proc_signal_with_audittoken`, resolved at run time.
    public static let system = AuditedSignaller(send: resolveSystemSend(), match: { $0.liveMatch() })

    /// True when audited signals are available.
    public var isSupported: Bool { send != nil }

    /// Signals the saved process after it is verified again.
    /// - Throws: `.unavailable` when the signal, the owner, or the identity cannot be verified;
    ///   `.processFailed` when the kernel refuses the signal. Nothing falls back to `kill(pid)`.
    public func signal(_ identity: ProcessIdentity, with signal: Int32) throws {
        guard Self.allowedSignals.contains(signal), identity.userID == geteuid(), identity.processID != getpid(),
            let words = identity.auditWords, words.count == 8, match(identity) == .running
        else { throw JerdError.unavailable("Process ownership cannot be verified. No process was signalled.") }
        try deliver(signal, to: words)
    }

    /// Continues a paused saved process (`SIGSTOP`, a debugger), so that it can act on the graceful
    /// signal: a paused process keeps a caught signal pending until it continues.
    ///
    /// A process that is not verified again as the same running process of this user gets nothing.
    /// That is safe: a paused process that stays paused does not stop, so the recovery wait times
    /// out and keeps the record.
    /// - Throws: `.unavailable` when the system cannot send audited signals; `.processFailed` when
    ///   the kernel refuses the signal.
    public func resume(_ identity: ProcessIdentity) throws {
        guard identity.userID == geteuid(), identity.processID != getpid(), let words = identity.auditWords,
            words.count == 8, match(identity) == .running
        else { return }
        try deliver(SIGCONT, to: words)
    }

    private func deliver(_ signal: Int32, to words: [UInt32]) throws {
        guard let send else {
            throw JerdError.unavailable(
                "This macOS version cannot safely signal a saved process. Stop the verified service manually.")
        }
        let code = send(words, signal)
        guard code == 0 || code == ESRCH else {
            throw JerdError.processFailed(
                "The saved process could not stop safely (\(code)). Its record was preserved.")
        }
    }

    /// libproc returns the error number, or -1 with `errno` set. Both forms are read.
    private static func resolveSystemSend() -> Send? {
        guard let library = dlopen(nil, RTLD_LAZY) else { return nil }
        defer { dlclose(library) }
        guard let symbol = dlsym(library, "proc_signal_with_audittoken") else { return nil }
        typealias Function = @convention(c) (UnsafeMutablePointer<audit_token_t>, Int32) -> Int32
        let function = unsafeBitCast(symbol, to: Function.self)
        return { words, signal in
            var token = audit_token_t()
            withUnsafeMutableBytes(of: &token) { buffer in
                words.withUnsafeBytes { buffer.copyMemory(from: $0) }
            }
            errno = 0
            let result = function(&token, signal)
            return errorNumber(returned: result, errno: errno)
        }
    }

    /// The `errno` value of a libproc call: the returned value, or `errno` when the call returned -1.
    static func errorNumber(returned: Int32, errno: Int32) -> Int32 {
        returned == -1 ? errno : returned
    }
}
